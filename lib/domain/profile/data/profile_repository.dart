import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/domain/profile/data/profile_parser.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/data/subscription_fetch.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/profile/model/profile_patch.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 订阅仓库 - 管理订阅的增删改查和配置文件下载
///
/// 所有对订阅列表的写入都经 [ProfileStore.commit] 串行提交；慢操作（网络、
/// 归一化）在锁外完成，落地前由 plan 校验输入是否仍然成立。
class ProfileRepository {
  ProfileRepository({
    required this.dio,
    required this.configDir,
    required this.prefs,
    required this.boxService,
    ProfileStore? store,
    DateTime Function()? clock,
    this.defaultNames = const ProfileDefaultNames(),
  }) : store = store ?? ProfileStore(prefs: prefs, configDir: configDir),
       _now = clock ?? DateTime.now;

  /// 订阅缺名称时用的默认名（provider 注入本地化文案）。
  final ProfileDefaultNames defaultNames;

  /// 取当前时间；测试注入固定时钟，避免靠真实等待制造「更晚的时间」。
  final DateTime Function() _now;

  final Dio dio;

  /// 配置文件存储目录
  final Directory configDir;

  final SharedPreferences prefs;

  /// 用于把订阅原始内容（Clash YAML / vless 链接列表 / sing-box JSON）
  /// 归一化成 sing-box JSON。native 的 `parse` 入口会原地覆盖文件。
  final BoxService boxService;

  /// 订阅存储（进程级单例，锁与 in-flight 表都在它身上）。
  final ProfileStore store;

  static Map<String, String>? _userAgentHeaders(String? customUserAgent) {
    if (customUserAgent == null || customUserAgent.trim().isEmpty) return null;

    return {'User-Agent': customUserAgent.trim()};
  }

  /// 获取所有订阅（容错读取：坏条目被隔离，永不抛出）。
  List<ProfileEntity> getAll() => store.read();

  /// 获取当前激活的订阅
  ProfileEntity? getActive() {
    final view = store.view();
    final id = view.activeId;
    return id == null ? null : view.find(id);
  }

  /// 设置激活的订阅。订阅不存在则忽略。
  Future<void> setActive(String profileId) async {
    final result = await store.commit<void>((view) {
      if (view.find(profileId) == null) return const Plan<void>.unchanged();
      if (view.activeId == profileId && view.storedActiveId == profileId) {
        return const Plan<void>.unchanged();
      }
      return Plan<void>(activeId: Patch<String>.set(profileId));
    });
    _throwIfFailed(result);
  }

  /// 直接导入单节点 / 内嵌订阅内容（ss:// vless:// trojan:// hysteria2:// vmess://
  /// 等代理 URI，或者一段已经是 Clash YAML / sing-box JSON 的文本）。
  ///
  /// 不走 HTTP 获取，把内容当订阅 body 直接喂给 native parse。
  /// 适用：剪贴板粘贴的单节点 URI、本地手动备份的配置内容。
  Future<ProfileEntity> addByContent(
    String content, {
    required String name,
  }) async {
    final id = const Uuid().v4();
    final staging = await store.createStagingFile(id);
    try {
      await _normalizeAndWrite(rawBody: content, output: staging);

      // 补齐 parse/raw JSON 输出中的配置结构：
      // ss:// / vless:// 单 URI 解析出来通常只有一个代理 outbound，没有 direct、
      // 没有 selector group、没有 route.final。RuntimeConfigBuilder 智能模式
      // 注入的 `outbound: 'direct'` 规则会找不到 direct outbound，整条路由失效，
      // 流量绕过 TUN 走系统默认链路。
      if (await staging.exists()) {
        await _ensureMinimalProfileStructure(staging);
      }

      final entity = ProfileEntity(
        id: id,
        // 不存完整 URI 到 url（可能含敏感凭据 / 密码）
        name: name.trim().isEmpty ? defaultNames.local() : name.trim(),
        url: 'content://${_truncate(content, 24)}',
        lastUpdate: _now(),
        inc: store.newInc(),
      );
      final result = await store.commit<ProfileEntity>(
        (view) => _planAdd(view, entity, staging),
      );
      _throwIfFailed(result);
      return result.value!;
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// 新增订阅的 plan：首条（当前没有激活订阅）自动激活，判断发生在锁内。
  Plan<ProfileEntity> _planAdd(
    ProfileListView view,
    ProfileEntity entity,
    File staging,
  ) {
    final isFirst = view.activeId == null;
    return Plan<ProfileEntity>(
      value: entity.copyWith(active: isFirst),
      profiles: [...view.profiles, entity],
      activeId: isFirst ? Patch<String>.set(entity.id) : const Patch.unset(),
      staged: [StagedConfig(entity.id, staging)],
    );
  }

  /// 给 native parse 出的精简 profile 补齐：
  /// - outbounds: 缺 direct 加 direct；缺 selector 自动包装出 `proxy` selector
  /// - route.final: 缺则指向 proxy（或第一个非 direct outbound）
  /// - inbounds: 缺则补 tun + mixed（移动端用 tun，桌面端 RuntimeConfigBuilder
  ///   会 strip 掉，最后 fork 自己接管）
  /// 已有这些字段则保留不动。
  Future<void> _ensureMinimalProfileStructure(File file) async {
    final raw = await file.readAsString();
    final Map<String, dynamic> cfg;
    try {
      cfg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // 不是 JSON（StubBoxService fallback 写的原文），不动
      return;
    }

    final outbounds = (cfg['outbounds'] as List?)?.cast<dynamic>() ?? [];

    var changed = false;
    final hasDirect = outbounds.any((o) => o is Map && o['type'] == 'direct');
    if (!hasDirect) {
      outbounds.add({'type': 'direct', 'tag': 'direct'});
      changed = true;
    }

    const groupTypes = {'selector', 'urltest', 'url_test'};
    final removedUrlTestTags = <String>{};
    outbounds.removeWhere((o) {
      if (o is! Map || !{'urltest', 'url_test'}.contains(o['type'])) {
        return false;
      }
      final tag = o['tag'];
      if (tag is String) removedUrlTestTags.add(tag);
      return true;
    });
    if (removedUrlTestTags.isNotEmpty) {
      changed = true;
    }

    final tagsSet = <String>{
      for (final o in outbounds)
        if (o is Map && o['tag'] is String) o['tag'] as String,
    };
    final tagTypes = <String, String>{
      for (final o in outbounds)
        if (o is Map && o['tag'] is String && o['type'] is String)
          o['tag'] as String: o['type'] as String,
    };
    bool isLeafProxyTag(String tag) {
      final type = tagTypes[tag];
      return type != null &&
          type != 'direct' &&
          type != 'dns' &&
          type != 'block' &&
          !groupTypes.contains(type);
    }

    final proxyTags = outbounds
        .where(
          (o) =>
              o is Map &&
              o['tag'] is String &&
              o['type'] != 'direct' &&
              o['type'] != 'dns' &&
              o['type'] != 'block' &&
              !groupTypes.contains(o['type']),
        )
        .map((o) => (o as Map)['tag'] as String)
        .toList();
    String? preferredDefaultFor(List<String> tags) {
      if (tags.isEmpty) return null;
      return tags.firstWhere(
        (tag) => !_isLikelyInformationalProxyTag(tag),
        orElse: () => tags.first,
      );
    }

    bool shouldReplaceDefault(Object? current, List<String> tags) {
      if (current is! String || !tags.contains(current)) return true;
      final preferred = preferredDefaultFor(tags);
      return preferred != null &&
          preferred != current &&
          _isLikelyInformationalProxyTag(current);
    }

    Map<dynamic, dynamic>? proxySelector;
    for (final outbound in outbounds) {
      if (outbound is! Map || !groupTypes.contains(outbound['type'])) {
        continue;
      }
      final current =
          (outbound['outbounds'] as List?)
              ?.whereType<String>()
              .where(tagsSet.contains)
              .toList() ??
          <String>[];
      final currentLeafTags = current.where(isLeafProxyTag).toList();
      if (outbound['type'] == 'selector' && outbound['tag'] == 'proxy') {
        proxySelector = outbound;
      }
      if (currentLeafTags.length != current.length &&
          outbound['type'] == 'selector') {
        outbound['outbounds'] = currentLeafTags;
        final currentDefault = outbound['default'];
        if (shouldReplaceDefault(currentDefault, currentLeafTags)) {
          outbound['default'] = preferredDefaultFor(currentLeafTags);
        }
        changed = true;
      }
      if (currentLeafTags.isEmpty && proxyTags.isNotEmpty) {
        outbound['outbounds'] = proxyTags;
        if (shouldReplaceDefault(outbound['default'], proxyTags)) {
          outbound['default'] = preferredDefaultFor(proxyTags);
        }
        changed = true;
      }
    }

    if (proxySelector != null && proxyTags.isNotEmpty) {
      final current =
          (proxySelector['outbounds'] as List?)
              ?.whereType<String>()
              .where(isLeafProxyTag)
              .toList() ??
          <String>[];
      final currentDefault = proxySelector['default'];
      if (!listEquals(current, proxyTags) ||
          shouldReplaceDefault(currentDefault, proxyTags)) {
        proxySelector['outbounds'] = proxyTags;
        proxySelector['default'] =
            shouldReplaceDefault(currentDefault, proxyTags)
            ? preferredDefaultFor(proxyTags)
            : currentDefault;
        changed = true;
      }
    }

    if (proxyTags.isNotEmpty) {
      Map<dynamic, dynamic>? existingProxy;
      for (final outbound in outbounds) {
        if (outbound is Map &&
            outbound['tag'] == 'proxy' &&
            outbound['type'] == 'selector') {
          existingProxy = outbound;
          break;
        }
      }
      if (existingProxy != null) {
        final current =
            (existingProxy['outbounds'] as List?)
                ?.whereType<String>()
                .where(isLeafProxyTag)
                .toList() ??
            <String>[];
        final currentDefault = existingProxy['default'];
        if (!listEquals(current, proxyTags) ||
            shouldReplaceDefault(currentDefault, proxyTags)) {
          existingProxy['outbounds'] = proxyTags;
          existingProxy['default'] =
              shouldReplaceDefault(currentDefault, proxyTags)
              ? preferredDefaultFor(proxyTags)
              : currentDefault;
          changed = true;
        }
      } else {
        outbounds.insert(0, {
          'type': 'selector',
          'tag': 'proxy',
          'outbounds': proxyTags,
          'default': preferredDefaultFor(proxyTags),
        });
        tagsSet.add('proxy');
        tagTypes['proxy'] = 'selector';
        changed = true;
      }
    }

    String? normalizeOutboundReference(dynamic value) {
      if (value is! String) return null;
      final type = tagTypes[value];
      final shouldUseProxy =
          removedUrlTestTags.contains(value) ||
          !tagsSet.contains(value) ||
          type == 'urltest' ||
          type == 'url_test' ||
          (type == 'selector' && value != 'proxy');
      if (!shouldUseProxy) return value;
      if (proxyTags.isNotEmpty && tagsSet.contains('proxy')) return 'proxy';
      if (tagsSet.contains('direct')) return 'direct';
      return null;
    }

    final route = (cfg['route'] is Map<String, dynamic>)
        ? cfg['route'] as Map<String, dynamic>
        : <String, dynamic>{};
    final finalTag = route['final'];
    final finalType = finalTag is String ? tagTypes[finalTag] : null;
    final shouldRouteViaProxy =
        proxyTags.isNotEmpty &&
        tagsSet.contains('proxy') &&
        finalTag != 'proxy';
    if (shouldRouteViaProxy ||
        finalTag is! String ||
        !tagsSet.contains(finalTag) ||
        finalType == 'urltest' ||
        finalType == 'url_test') {
      // 优先 proxy selector；没有就用第一个非 direct 的。
      //
      // 先落到有类型的局部变量再取 'tag'，不要把 `firstWhere(...)['tag']` 串成
      // 一行：`firstWhere` 在 `List<dynamic>` 上返回 dynamic，直接下标就是一次
      // dynamic 调用——类型对不上时不会在这里报错，而是在几层之后以一个跟现场
      // 无关的 NoSuchMethodError 冒出来。
      final Object? fallbackOutbound = outbounds.firstWhere(
        (o) => o is Map && o['type'] != 'direct',
        orElse: () => {'tag': 'direct'},
      );
      route['final'] = tagsSet.contains('proxy')
          ? 'proxy'
          : (fallbackOutbound is Map ? fallbackOutbound['tag'] : 'direct');
      cfg['route'] = route;
      changed = true;
    }
    final routeRules = route['rules'];
    if (routeRules is List) {
      for (final rule in routeRules) {
        if (rule is! Map) continue;
        final current = rule['outbound'];
        final normalized = normalizeOutboundReference(current);
        if (normalized != null && normalized != current) {
          rule['outbound'] = normalized;
          changed = true;
        }
      }
    }
    final routeRuleSet = route['rule_set'];
    if (routeRuleSet is List) {
      for (final ruleSet in routeRuleSet) {
        if (ruleSet is! Map) continue;
        final current = ruleSet['download_detour'];
        final normalized = normalizeOutboundReference(current);
        if (normalized != null && normalized != current) {
          ruleSet['download_detour'] = normalized;
          changed = true;
        }
      }
    }

    // dns.servers 缺失会让 RuntimeConfigBuilder 注入的 `server: "local"` 引用
    // 不到任何 server → sing-box DNS 阶段没有解析后端 → Chrome 上 DNS_PROBE_
    // FINISHED_NO_INTERNET。补上标准两 server：local（系统）+ remote（走代理）。
    final dns = (cfg['dns'] is Map<String, dynamic>)
        ? cfg['dns'] as Map<String, dynamic>
        : <String, dynamic>{};
    final dnsServers = (dns['servers'] as List?)?.cast<dynamic>() ?? [];
    if (dnsServers.isEmpty) {
      // 3 层 DNS server 链（参考 sing-box 推荐套路）：
      //   remote → 远程 DNS（走代理）。用 DoH 而不是 udp://1.1.1.1，因为很多 SS /
      //            Trojan 节点不转发 UDP，udp DNS 永远超时。RuntimeConfigBuilder
      //            每次 connect 会按用户 NetworkSettings.remoteDnsAddress 覆盖。
      //   direct → 直连 DNS（用来解析 remote 自己的域名 + 国内域名）
      //   local  → 系统 DNS（用来解析 direct 自己的域名 fallback）
      dnsServers.addAll([
        {'tag': 'remote', 'address': 'https://1.1.1.1/dns-query'},
        {'tag': 'direct', 'address': '1.1.1.1', 'detour': 'direct'},
        {'tag': 'local', 'address': 'local', 'detour': 'direct'},
      ]);
      dns['servers'] = dnsServers;
      dns['final'] = dns['final'] ?? 'remote';
      cfg['dns'] = dns;
      changed = true;
    }
    for (final server in dnsServers) {
      if (server is! Map) continue;
      final current = server['detour'];
      final normalized = normalizeOutboundReference(current);
      if (normalized != null && normalized != current) {
        server['detour'] = normalized;
        changed = true;
      }
    }

    // tun + mixed 一并使用 App 自己验证过的 schema。服务端 raw sing-box JSON
    // 可能带 `address`、`users` 等当前 mobile core 不接受的字段。
    //
    // 桌面端这两条都会被 RuntimeConfigBuilder strip 掉，由 fork 自动 append。
    final standardInbounds = <Map<String, dynamic>>[
      {
        'type': 'tun',
        'tag': 'tun-in',
        'stack': 'mixed',
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        'endpoint_independent_nat': true,
        'inet4_address': ['172.19.0.1/28'],
        'inet6_address': ['fdfe:dcba:9876::1/126'],
        'sniff': true,
        'sniff_override_destination': true,
      },
      {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': 2080,
        'sniff': true,
        'sniff_override_destination': true,
      },
    ];
    if (jsonEncode(cfg['inbounds'] ?? []) != jsonEncode(standardInbounds)) {
      cfg['inbounds'] = standardInbounds;
      changed = true;
    }

    if (changed) {
      cfg['outbounds'] = outbounds;
      await file.writeAsString(jsonEncode(cfg));
    }
  }

  static String _truncate(String s, int n) {
    final stripped = s.trim().replaceAll(RegExp(r'\s+'), '');
    return stripped.length <= n ? stripped : '${stripped.substring(0, n)}...';
  }

  static bool _isLikelyInformationalProxyTag(String tag) {
    final lower = tag.toLowerCase();
    return lower.contains('官网') ||
        lower.contains('官方') ||
        lower.contains('网址') ||
        lower.contains('订阅') ||
        lower.contains('套餐') ||
        lower.contains('流量') ||
        lower.contains('剩余') ||
        lower.contains('到期') ||
        lower.contains('过期') ||
        lower.contains('expire') ||
        lower.contains('traffic') ||
        lower.contains('website') ||
        lower.contains('official');
  }

  /// 添加订阅（下载并解析）
  /// [customName] 用户自定义名称，不传则从响应头自动解析
  ///
  /// 去重：同一 URL（trim 后比较）重复添加不会产生第二条记录——
  /// 找到已有的那条，直接复用 [update] 触发一次真实的重新拉取（并按需
  /// 更新名称），不新建 profile / 不新建配置文件。去重判断在提交的 plan 内
  /// 再做一次，所以拉取期间别处新增了同 URL 订阅也不会产生重复。
  Future<ProfileEntity> addByUrl(String url, {String? customName}) async {
    final normalizedUrl = url.trim();
    for (final existing in store.read()) {
      if (existing.url.trim() == normalizedUrl) {
        return _refreshExisting(existing.id, customName);
      }
    }

    // 先用自己的 UA 请求；只有当响应明显不可用（网页 / 零节点）时才依次换用
    // 通用客户端 UA 重试——详见 subscription_fetch.dart。
    final fetched = await fetchSubscriptionWithUserAgentFallback(
      primaryUserAgent: kDefaultUserAgent,
      fetch: (userAgent) async {
        final response = await dio.get<String>(
          normalizedUrl,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
            headers: {'User-Agent': userAgent},
          ),
        );
        final headers = <String, List<String>>{};
        response.headers.forEach((name, values) {
          headers[name.toLowerCase()] = values;
        });
        return SubscriptionResponse(
          body: response.data ?? '',
          contentType: response.headers.value('content-type'),
          headers: headers,
        );
      },
    );

    var profile = ProfileParser.parse(
      normalizedUrl,
      fetched.response.headers,
      fallbackName: defaultNames.remote(),
    );

    // 优先使用用户自定义名称
    if (customName != null && customName.trim().isNotEmpty) {
      profile = profile.copyWith(name: customName.trim());
    }

    // 回退命中时，把真正管用的那个 UA 记在订阅上。不记的话：导入靠回退成功了，
    // 但下一次刷新又用回自身 UA、面板再发一份空配置，节点列表会被当场清空——
    // 那比一开始就导入失败更糟。写进 customUserAgent 还有个好处：用户在订阅
    // 详情页看得见、也能自己改。
    if (fetched.userAgent != kDefaultUserAgent) {
      profile = profile.copyWith(customUserAgent: fetched.userAgent);
    }
    profile = profile.copyWith(inc: store.newInc(), rev: 1, lastUpdate: _now());

    // 归一化：先把原始响应写到 tempFile（输入），让 native parse 读它、
    // 解析（Clash YAML / base64 / sing-box JSON）后**写到**暂存文件（输出）。
    final staging = await store.createStagingFile(profile.id);
    String? duplicateId;
    try {
      final needsStructureRepair = await _normalizeAndWrite(
        rawBody: fetched.response.body,
        output: staging,
      );
      if (needsStructureRepair) {
        await _ensureMinimalProfileStructure(staging);
      }

      final entity = profile;
      final result = await store.commit<ProfileEntity>((view) {
        for (final existing in view.profiles) {
          if (existing.url.trim() == normalizedUrl) {
            duplicateId = existing.id;
            return const Plan<ProfileEntity>.unchanged();
          }
        }
        return _planAdd(view, entity, staging);
      });
      _throwIfFailed(result);
      if (duplicateId == null) return result.value!;
    } finally {
      await _deleteQuietly(staging);
    }
    // 拉取期间别处已经加了同 URL 的订阅：本次结果作废，退回「刷新已有那条」。
    return _refreshExisting(duplicateId!, customName);
  }

  Future<ProfileEntity> _refreshExisting(
    String profileId,
    String? customName,
  ) async {
    if (customName != null && customName.trim().isNotEmpty) {
      await editProfile(profileId, newName: customName.trim());
    }
    try {
      return await update(profileId);
    } on ProfileUpdateStaleException {
      // 刷新途中这条订阅又被改动（或被删）：本次「再拉一次」作废，但「导入」这个
      // 动作的目的——这条订阅存在——已经达成，不能把预期内的取消报成导入失败。
      final existing = store.find(profileId);
      if (existing == null) rethrow;
      return existing;
    }
  }

  /// 更新指定订阅。
  ///
  /// 两段式：①锁外读取请求输入 `(id, inc, rev, url, ua)`、发请求、归一化到
  /// 暂存文件；②锁内 [ProfileStore.commit] 校验输入仍然成立才落地。相同输入的
  /// 并发调用共享同一个 Future；输入不同（比如期间改了 URL）互不共享。
  ///
  /// 期间订阅被删除 / 编辑 / 换代时结果被丢弃，抛 [ProfileUpdateStaleException]。
  /// 这是**预期内的取消**而不是失败：调用方应静默跳过（或按「订阅仍存在」处理），
  /// 不要提示刷新失败。可用 `isStaleRefresh`（profile_failures.dart）判断。
  Future<ProfileEntity> update(String profileId) async {
    final current = store.find(profileId);
    if (current == null) throw Exception('Profile not found/订阅不存在');
    return store.dedupe<ProfileEntity>(
      _refreshKey(current),
      () => _refresh(current),
    );
  }

  static String _refreshKey(ProfileEntity e) =>
      [e.id, e.inc, '${e.rev}', e.url, e.customUserAgent ?? ''].join('\u0000');

  static bool _sameRefreshInput(ProfileEntity a, ProfileEntity b) =>
      a.id == b.id &&
      a.inc == b.inc &&
      a.rev == b.rev &&
      a.url == b.url &&
      (a.customUserAgent ?? '') == (b.customUserAgent ?? '');

  Future<ProfileEntity> _refresh(ProfileEntity request) async {
    final response = await dio.get<String>(
      request.url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        headers: _userAgentHeaders(request.customUserAgent),
      ),
    );

    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values;
    });

    // 更新订阅信息
    final parsed = ProfileParser.parse(
      request.url,
      headers,
      fallbackName: defaultNames.remote(),
    );

    // 重新归一化（参见 addByUrl 注释）：写到暂存文件，落地前不碰正式文件。
    final staging = await store.createStagingFile(request.id);
    try {
      final needsStructureRepair = await _normalizeAndWrite(
        rawBody: response.data ?? '',
        output: staging,
      );
      if (needsStructureRepair) {
        await _ensureMinimalProfileStructure(staging);
      }

      final result = await store.commit<ProfileEntity>((view) {
        final cur = view.find(request.id);
        if (cur == null || !_sameRefreshInput(cur, request)) {
          return const Plan<ProfileEntity>.stale();
        }
        final updated = cur.copyWith(
          name: cur.name.trim().isEmpty ? parsed.name : cur.name,
          lastUpdate: _now(),
          subInfo: _mergeSubInfo(cur.subInfo, parsed.subInfo),
          rev: cur.rev + 1,
        );
        return Plan<ProfileEntity>(
          value: updated,
          profiles: _replaced(view.profiles, updated),
          staged: [StagedConfig(cur.id, staging)],
        );
      });
      if (result.isStale) throw ProfileUpdateStaleException(request.id);
      _throwIfFailed(result);
      return result.value!;
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// 响应头没带流量信息就保留旧的；带了就用新的已知字段，**但保留旧对象里的
  /// 未知字段**（`extra`）——整体替换会让新版本写入的字段在一次刷新后消失。
  static SubscriptionInfo? _mergeSubInfo(
    SubscriptionInfo? current,
    SubscriptionInfo? refreshed,
  ) {
    if (refreshed == null) return current;
    if (current == null) return refreshed;
    return SubscriptionInfo(
      upload: refreshed.upload,
      download: refreshed.download,
      total: refreshed.total,
      expire: refreshed.expire,
      webPageUrl: refreshed.webPageUrl,
      supportUrl: refreshed.supportUrl,
      extra: current.extra,
    );
  }

  static List<ProfileEntity> _replaced(
    List<ProfileEntity> profiles,
    ProfileEntity updated,
  ) => [for (final e in profiles) e.id == updated.id ? updated : e];

  /// 把 [entity] 里**用户可编辑的字段**（名称、URL、更新间隔、自定义 UA、
  /// 高级配置）应用到同 id 的订阅上；`lastUpdate` / `subInfo` / `rev` / `inc` /
  /// 未知字段一律以存储中的最新值为准，不受 [entity] 影响。
  ///
  /// 旧实现是整实体替换：调用方手里的旧快照会把刷新期间写入的 `lastUpdate` /
  /// `subInfo` 写回去覆盖掉。现在这个方法只是补丁的一种便捷写法；新代码请直接
  /// 用 [editProfile] 的 `patch`，只带真正要改的字段。
  Future<void> updateProfile(ProfileEntity entity) {
    final advanced = entity.advancedConfig;
    return editProfile(
      entity.id,
      patch: ProfilePatch(
        name: Patch<String>.set(entity.name),
        url: Patch<String>.set(entity.url),
        updateInterval: Patch<Duration>.set(entity.updateInterval),
        customUserAgent: entity.customUserAgent == null
            ? const Patch<String>.clear()
            : Patch<String>.set(entity.customUserAgent!),
        advancedConfig: advanced == null
            ? const Patch<AdvancedConfigPatch>.clear()
            : Patch<AdvancedConfigPatch>.set(
                AdvancedConfigPatch(
                  remoteDnsOverride: advanced.remoteDnsOverride == null
                      ? const Patch<String>.clear()
                      : Patch<String>.set(advanced.remoteDnsOverride!),
                  muxEnabled: Patch<bool>.set(advanced.muxEnabled),
                  muxProtocol: Patch<String>.set(advanced.muxProtocol),
                  muxConcurrency: Patch<int>.set(advanced.muxConcurrency),
                  fragmentEnabled: Patch<bool>.set(advanced.fragmentEnabled),
                  fragmentRange: advanced.fragmentRange == null
                      ? const Patch<String>.clear()
                      : Patch<String>.set(advanced.fragmentRange!),
                ),
              ),
      ),
    );
  }

  /// 编辑订阅。
  ///
  /// 推荐传 [patch]：每个字段三态（不动 / 设置 / 清除），一次提交完成，
  /// 只改被指定的字段。[newName] / [newUrl] 是旧调用方式的快捷写法，trim 后
  /// 为空则跳过；与 [patch] 同时给出时以 [patch] 中显式指定的字段为准。
  /// 订阅不存在或补丁没有造成任何变化则不写入（不增加 `rev`）。
  Future<void> editProfile(
    String profileId, {
    String? newName,
    String? newUrl,
    ProfilePatch? patch,
  }) async {
    final effective = ProfilePatch(
      name: (patch != null && !patch.name.isUnset)
          ? patch.name
          : (newName != null
                ? Patch<String>.set(newName)
                : const Patch.unset()),
      url: (patch != null && !patch.url.isUnset)
          ? patch.url
          : (newUrl != null ? Patch<String>.set(newUrl) : const Patch.unset()),
      updateInterval: patch?.updateInterval ?? const Patch.unset(),
      customUserAgent: patch?.customUserAgent ?? const Patch.unset(),
      advancedConfig: patch?.advancedConfig ?? const Patch.unset(),
    );
    final result = await store.commit<void>((view) {
      final cur = view.find(profileId);
      if (cur == null) return const Plan<void>.unchanged();
      final next = _applyPatch(cur, effective);
      if (jsonEncode(next.toJson()) == jsonEncode(cur.toJson())) {
        return const Plan<void>.unchanged();
      }
      return Plan<void>(
        profiles: _replaced(view.profiles, next.copyWith(rev: cur.rev + 1)),
      );
    });
    _throwIfFailed(result);
  }

  static ProfileEntity _applyPatch(ProfileEntity cur, ProfilePatch patch) {
    String? trimmed(Patch<String> field) {
      if (!field.isSet) return null;
      final value = field.value.trim();
      return value.isEmpty ? null : value;
    }

    final advanced = patch.advancedConfig;
    return cur.copyWith(
      name: trimmed(patch.name),
      url: trimmed(patch.url),
      updateInterval: patch.updateInterval.isSet
          ? patch.updateInterval.value
          : null,
      customUserAgent: patch.customUserAgent.isUnset
          ? cur.customUserAgent
          : patch.customUserAgent.resolve(null),
      advancedConfig: advanced.isUnset
          ? cur.advancedConfig
          : advanced.isClear
          ? null
          : advanced.value.applyTo(cur.advancedConfig),
    );
  }

  /// 插入或更新订阅（按 id 匹配；备份恢复时使用）。
  ///
  /// 这是一次「新的订阅对象」：无论备份里带了什么，`inc` 一律重新生成（备份
  /// 不携带本机代际），使恢复前发出的旧刷新、旧附属数据写入全部失效。`active`
  /// 字段被忽略——激活用 [setActive]。id 不合法抛 [ArgumentError]。
  Future<void> upsert(Map<String, dynamic> json) async {
    final entity = ProfileEntity.fromJson(json);
    if (!ProfileStore.isValidId(entity.id)) {
      throw ArgumentError.value(entity.id, 'id', '订阅 id 不合法');
    }
    final result = await store.commit<void>((view) {
      final existing = view.find(entity.id);
      final next = entity.copyWith(
        inc: store.newInc(),
        rev: existing == null ? entity.rev : existing.rev + 1,
      );
      return Plan<void>(
        profiles: existing == null
            ? [...view.profiles, next]
            : _replaced(view.profiles, next),
      );
    });
    _throwIfFailed(result);
  }

  /// 删除订阅：同一次提交里移除条目、必要时切换激活、清理配置文件与附属键
  /// （`proxy_selection_<id>` / `proxy_delays_<id>`）。
  Future<void> delete(String profileId) async {
    final result = await store.commit<void>((view) {
      if (view.find(profileId) == null) return const Plan<void>.unchanged();
      final remaining = [
        for (final e in view.profiles)
          if (e.id != profileId) e,
      ];
      var active = const Patch<String>.unset();
      if (view.activeId == profileId) {
        // 删掉的是激活的：切到剩下的第一条；一条不剩则清空激活。
        active = remaining.isEmpty
            ? const Patch<String>.clear()
            : Patch<String>.set(remaining.first.id);
      }
      return Plan<void>(
        profiles: remaining,
        activeId: active,
        removedProfileIds: [profileId],
      );
    });
    _throwIfFailed(result);
  }

  /// 更新全部订阅
  Future<void> updateAll() async {
    for (final profile in store.read()) {
      try {
        await update(profile.id);
      } on StoreReadOnlyException {
        rethrow; // 只读模式下每一条都会失败，别装作更新成功了
      } catch (_) {
        // 单个更新失败（含期间被改动而作废）不影响其他
      }
    }
  }

  void _throwIfFailed(CommitResult<Object?> result) {
    if (result.isFailed) {
      throw ProfileStorageException(result.error ?? 'unknown');
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 把订阅原始 body 归一化成 sing-box JSON 并写到 [output]。
  ///
  /// **优先**：如果 raw 是合法 sing-box JSON（`{` 开头，能 jsonDecode 出 outbounds），
  /// 先直接写出原文——保留 inbounds / dns / route / rule_set 等完整字段，
  /// 再走结构修复，避免订阅自带的多级 selector / urltest 让 UI 和运行态退回
  /// 不稳定分组。
  ///
  /// **否则**：调 native `parse(configPath, tempPath)`（Clash YAML / vless 链接 → sing-box JSON），
  /// 但 parse 后的输出只剩 outbounds，需要 RuntimeConfigBuilder 在 connect 时补全。
  Future<bool> _normalizeAndWrite({
    required String rawBody,
    required File output,
  }) async {
    await output.parent.create(recursive: true);
    final normalized = File('${output.path}.next');
    final trimmed = rawBody.trimLeft();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        final outbounds = decoded['outbounds'];
        if (outbounds is List && outbounds.isNotEmpty) {
          await _replaceAtomically(normalized, output, rawBody);
          debugPrint('[Profile] raw 已是 sing-box JSON，跳过 native parse');
          return true;
        }
      } catch (_) {
        // 不是合法 JSON 就 fallthrough 到 native parse
      }
    }

    if (boxService is StubBoxService) {
      await _replaceAtomically(normalized, output, rawBody);
      return false;
    }
    final tempFile = File('${output.path}.tmp');
    try {
      if (await normalized.exists()) await normalized.delete();
      await tempFile.writeAsString(rawBody);
      debugPrint('[Profile] native validateConfig start');
      final err = await boxService
          .validateConfig(normalized.path, tempFile.path)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const ProfileValidationException('配置解析超时'),
          );
      debugPrint('[Profile] native validateConfig done');
      if (err != null && err.isNotEmpty) {
        throw ProfileValidationException(err);
      }
      if (!await normalized.exists()) {
        throw const ProfileValidationException(
          'validateConfig did not write output',
        );
      }
      await _commitNormalized(normalized, output);
      return true;
    } catch (e, st) {
      debugPrint('[Profile] _normalizeAndWrite 抛异常: $e\n$st');
      if (e is ProfileValidationException) rethrow;
      throw ProfileValidationException(e.toString());
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (await normalized.exists()) {
        try {
          await normalized.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _replaceAtomically(
    File staging,
    File output,
    String content,
  ) async {
    await staging.writeAsString(content);
    await _commitNormalized(staging, output);
  }

  Future<void> _commitNormalized(File staging, File output) async {
    await staging.rename(output.path);
  }

  /// 配置文件路径。id 不合法（可能逃出 profiles 目录）抛 [ArgumentError]。
  String configFilePath(String profileId) => store.configFilePath(profileId);
}

/// 订阅缺名称时的默认名。名称会持久化成用户数据（可改名），所以在创建时就用
/// 当前语言的文案；这里的英文只是未注入时（测试、无界面场景）的兜底。
class ProfileDefaultNames {
  const ProfileDefaultNames({
    this.local = _defaultLocal,
    this.remote = _defaultRemote,
  });

  static String _defaultLocal() => 'Local import';
  static String _defaultRemote() => 'Remote subscription';

  /// 本地导入（剪贴板 / 手动粘贴内容）的默认名。
  final String Function() local;

  /// 远程订阅（URL 与响应头都没给名称）的默认名。
  final String Function() remote;
}

/// 刷新期间订阅被删除 / 编辑 / 换代，本次结果已丢弃。
class ProfileUpdateStaleException implements Exception {
  const ProfileUpdateStaleException(this.profileId);

  final String profileId;

  @override
  String toString() =>
      'ProfileUpdateStaleException: 订阅 $profileId 在刷新期间已被修改或删除，本次结果已丢弃';
}

/// 订阅存储提交失败（磁盘 / 偏好写入失败，已还原）。
class ProfileStorageException implements Exception {
  const ProfileStorageException(this.cause);

  final Object cause;

  @override
  String toString() => 'ProfileStorageException: $cause';
}

class ProfileValidationException implements Exception {
  const ProfileValidationException(this.message);

  final String message;

  @override
  String toString() => 'ProfileValidationException: $message';
}

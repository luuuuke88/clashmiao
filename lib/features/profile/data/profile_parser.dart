import 'dart:convert';

import 'package:clashmiao/core/model/profile_entity.dart';
import 'package:uuid/uuid.dart';

/// 订阅链接解析器
///
/// 从订阅响应的 headers 中提取：名称、更新间隔、流量信息等
class ProfileParser {
  ProfileParser._();

  static const _infiniteTraffic = 9223372036854775807;
  static const _infiniteTime = 92233720368;

  /// 解析订阅响应
  static ProfileEntity parse(String url, Map<String, List<String>> headers) {
    var name = _parseName(url, headers);
    if (name.trim().isEmpty) name = '远程订阅';

    Duration? updateInterval;
    if (headers['profile-update-interval'] case [final intervalStr]) {
      updateInterval = Duration(hours: int.tryParse(intervalStr) ?? 1);
    }

    SubscriptionInfo? subInfo;
    if (headers['subscription-userinfo'] case [final infoStr]) {
      subInfo = _parseSubInfo(infoStr);
    }

    // 管理和客服链接
    if (subInfo != null) {
      if (headers['profile-web-page-url'] case [
        final pageUrl,
      ] when Uri.tryParse(pageUrl)?.hasScheme == true) {
        subInfo = subInfo.copyWith(webPageUrl: pageUrl);
      }
      if (headers['support-url'] case [
        final supportUrl,
      ] when Uri.tryParse(supportUrl)?.hasScheme == true) {
        subInfo = subInfo.copyWith(supportUrl: supportUrl);
      }
    }

    return ProfileEntity(
      id: const Uuid().v4(),
      name: name,
      url: url,
      active: false,
      lastUpdate: DateTime.now(),
      updateInterval: updateInterval ?? const Duration(hours: 1),
      subInfo: subInfo,
    );
  }

  /// 按优先级解析名称
  static String _parseName(String url, Map<String, List<String>> headers) {
    // 1. profile-title header
    if (headers['profile-title'] case [final title]) {
      if (title.startsWith('base64:')) {
        try {
          return utf8.decode(base64.decode(title.replaceFirst('base64:', '')));
        } catch (_) {}
      }
      return title.trim();
    }

    // 2. content-disposition header
    if (headers['content-disposition'] case [final disposition]) {
      final match = RegExp('filename="([^"]*)"').firstMatch(disposition);
      if (match != null && match.groupCount >= 1) {
        final fn = match.group(1) ?? '';
        if (fn.isNotEmpty) return fn;
      }
    }

    // 3. URL fragment（分享侧 `profiles_page.dart` 的 `profileShareUrl` 会把
    // 订阅名编码进 fragment；Uri.fragment 返回的是未解码的 percent-encoded
    // 原文，这里解码还原成人类可读的名称。解码失败（非法/截断的
    // percent-encoding）时不抛异常，原样返回 fragment 兜底。）
    final uri = Uri.tryParse(url);
    if (uri != null && uri.fragment.isNotEmpty) {
      try {
        return Uri.decodeComponent(uri.fragment);
      } catch (_) {
        return uri.fragment;
      }
    }

    // 4. URL 最后一段路径（去掉扩展名）
    if (uri != null) {
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final last = segments.last;
        return last.replaceFirst(RegExp(r'\.(json|yaml|yml|txt)[\s\S]*'), '');
      }
    }

    return '';
  }

  /// 解析 subscription-userinfo header
  static SubscriptionInfo? _parseSubInfo(String infoStr) {
    final parts = infoStr.split(';');
    final map = <String, int>{};
    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length == 2) {
        map[kv[0].trim()] = int.tryParse(kv[1].trim()) ?? 0;
      }
    }

    // header 里至少要有一个已知字段才算有效 userinfo；部分机场只给
    // total/expire 不给已用流量，缺的字段降级为 0 而不是丢弃整条
    // （丢弃会连到期时间一起消失）。
    if (map.isEmpty) return null;
    final upload = map['upload'] ?? 0;
    final download = map['download'] ?? 0;

    var total = map['total'] ?? 0;
    var expire = map['expire'] ?? 0;
    if (total == 0) total = _infiniteTraffic;
    if (expire == 0) expire = _infiniteTime;

    return SubscriptionInfo(
      upload: upload,
      download: download,
      total: total,
      expire: DateTime.fromMillisecondsSinceEpoch(expire * 1000),
    );
  }
}

// 分层依赖规则：纯 Dart、无 flutter_test 依赖，输入是「文件 → 它的全部 URI」。
//
// 规则来源见分层设计文档第 3 节。这里只判定项目内依赖边与 R1 模型纯净；
// R2（只用 package 导入）已由 `always_use_package_imports` lint 把守，不重复实现。
import 'import_scanner.dart';

/// domain 概念的固定先后顺序：只允许「后者依赖前者」。
/// 顺序本身就是依赖方向——新增概念必须在这里登记位置，否则判违规。
const kDomainOrder = ['config', 'profile', 'routing', 'connection'];

/// 一条违规。`toString` 单行输出，失败时可以整批打印、直接复制定位。
class Violation {
  const Violation(this.from, this.to, this.rule, this.hint);

  final String from;
  final String to;
  final String rule;
  final String hint;

  @override
  String toString() => '$from → $to · $rule · $hint';
}

/// 白名单条目：一条被豁免的 `features/<F> → features/<G>` 文件级依赖边。
class AllowedEdge {
  const AllowedEdge(this.from, this.to, this.reason);

  final String from;
  final String to;
  final String reason;

  @override
  String toString() => '$from → $to（$reason）';
}

const _lintRule = '层间依赖';
const _illegalAllowRule = '白名单条目非法';
const _purityRule = 'R1 模型纯净';
const _nonCanonicalUriRule = '非规范 URI';

const _knownLayers = {'core', 'shared', 'domain', 'features'};

/// 某个文件所处的「单元」：
/// - `core/<module>`、`shared/<module>`、`domain/<concept>`、`features/<feature>`
///   取前两段；
/// - `app/**` 是 `app`，`main.dart` 是 `main`；
/// - `*.g.dart` 与同目录的手写文件同层（R4：生成物不豁免）。
/// 层根目录下直接放的文件（如 `core/a.dart`）没有模块段，单元就是层本身。
/// 不在已知层里的路径返回 `null`，由调用方报违规，不静默放过。
class _Unit {
  const _Unit(this.layer, this.name);

  /// `core` / `shared` / `domain` / `features` / `app` / `main`。
  final String layer;

  /// 模块名（domain 概念、feature 名等）；层根下直接的文件为 `null`。
  final String? name;

  static _Unit? of(String path) {
    if (path == 'main.dart') return const _Unit('main', null);
    final parts = path.split('/');
    final layer = parts.first;
    if (layer == 'app') return const _Unit('app', null);
    if (!_knownLayers.contains(layer)) return null;
    return _Unit(layer, parts.length >= 3 ? parts[1] : null);
  }

  bool get isUnrestricted => layer == 'app' || layer == 'main';
}

bool _isFeatureEdge(AllowedEdge e) =>
    e.from.startsWith('features/') && e.to.startsWith('features/');

/// 白名单里不是 `features/<F> → features/<G>` 的非法条目。
/// [checkLayering]（逐条报违规）与 [checkAllowlist]（汇总问题）都从这里取，
/// 「什么算合法条目」只有这一份判定。
List<AllowedEdge> _illegalEntries(List<AllowedEdge> entries) => [
  for (final e in entries)
    if (!_isFeatureEdge(e)) e,
];

String _nonCanonicalUriHint(String uri, String reason) =>
    '非规范的 URI，请改用 package:clashmiao/ 导入（$reason）：$uri';

/// 层间依赖检查。[uris] 的键是 `lib/` 内相对路径，值是该文件的全部 URI。
///
/// 白名单**只**豁免 `features/<F> → features/<G>`：跨层的口子一旦能开，
/// 白名单就会变成架构的后门。所以两端不都在 `features/` 下的条目本身就是违规。
List<Violation> checkLayering(
  Map<String, List<String>> uris, {
  required List<AllowedEdge> allowlist,
}) {
  final violations = <Violation>[];

  for (final e in _illegalEntries(allowlist)) {
    violations.add(
      Violation(
        e.from,
        e.to,
        _illegalAllowRule,
        '白名单只能豁免 features/<F> → features/<G> 的依赖，其他层间依赖必须改代码',
      ),
    );
  }
  final allowed = {
    for (final e in allowlist)
      if (_isFeatureEdge(e)) '${e.from}\u0000${e.to}',
  };

  for (final entry in uris.entries) {
    final from = entry.key;
    final fromUnit = _Unit.of(from);
    if (fromUnit == null) {
      violations.add(
        Violation(
          from,
          '-',
          _lintRule,
          '文件不在 core/shared/domain/features/app 任何一层里，请归位',
        ),
      );
      continue;
    }
    for (final uri in entry.value) {
      final reason = nonCanonicalUriReason(uri, from: from);
      if (reason != null) {
        // 失败即关闭：非规范写法无法可靠还原成依赖边，不能当作「没有依赖」。
        violations.add(
          Violation(
            from,
            uri,
            _nonCanonicalUriRule,
            _nonCanonicalUriHint(uri, reason),
          ),
        );
        continue;
      }
      // app / main 只豁免「依赖方向」；URI 规范性对所有文件一视同仁（上面已查）。
      if (fromUnit.isUnrestricted) continue;
      final to = projectPath(uri, from: from);
      if (to == null) continue;
      final toUnit = _Unit.of(to);
      if (toUnit == null) {
        violations.add(
          Violation(
            from,
            to,
            _lintRule,
            '依赖目标不在 core/shared/domain/features/app 任何一层里',
          ),
        );
        continue;
      }
      final hint = _check(fromUnit, toUnit);
      if (hint == null) continue;
      if (allowed.contains('$from\u0000$to')) continue;
      violations.add(Violation(from, to, _lintRule, hint));
    }
  }
  return violations;
}

/// 判定单条边；合规返回 `null`，违规返回修法提示。
String? _check(_Unit from, _Unit to) {
  switch (from.layer) {
    case 'core':
      return to.layer == 'core' ? null : 'core 只能依赖 core，不能向上依赖 ${to.layer}';
    case 'shared':
      return (to.layer == 'core' || to.layer == 'shared')
          ? null
          : 'shared 只能依赖 core / shared，不能依赖 ${to.layer}';
    case 'domain':
      return _checkDomain(from, to);
    case 'features':
      if (to.layer == 'core' || to.layer == 'shared' || to.layer == 'domain') {
        return null;
      }
      if (to.layer == 'features') {
        return from.name == to.name
            ? null
            : 'feature 之间不能互相依赖：把共享部分下沉到 domain / shared；'
                  '页面跳转请通过 app 层的路由入口解耦';
      }
      return 'features 不能依赖 ${to.layer}（app 层只能被入口使用）';
  }
  return null;
}

String? _checkDomain(_Unit from, _Unit to) {
  // 先查自己的概念是否登记：未登记的概念连依赖 core 也不放过，
  // 否则新概念可以绕开顺序约束悄悄长出来。
  final fromIdx = kDomainOrder.indexOf(from.name ?? '');
  if (fromIdx < 0) {
    return 'domain 概念 ${from.name} 未在 kDomainOrder 登记顺序';
  }
  if (to.layer == 'core') return null;
  if (to.layer != 'domain') {
    return 'domain 只能依赖 core 与更靠前的 domain 概念，不能依赖 ${to.layer}';
  }
  final toIdx = kDomainOrder.indexOf(to.name ?? '');
  if (toIdx < 0) return 'domain 概念 ${to.name} 未在 kDomainOrder 登记顺序';
  if (from.name == to.name || toIdx < fromIdx) return null;
  return 'domain 顺序为 ${kDomainOrder.join(' < ')}，'
      '${from.name} 不能依赖更靠后的 ${to.name}';
}

/// R1 里不允许模型（及其传递依赖）碰到的外部 URI。
bool _isForbiddenExternal(String uri) =>
    uri == 'dart:io' ||
    uri == 'dart:ui' ||
    uri.startsWith('package:flutter/') ||
    uri.startsWith('package:hooks_riverpod/') ||
    uri.startsWith('package:riverpod/') ||
    uri.startsWith('package:flutter_riverpod/');

final _modelFile = RegExp(r'^domain/[^/]+/model/');
final _nonModelFile = RegExp(r'^domain/[^/]+/(data|application)/');

/// R1 模型纯净：从任何 `domain/*/model/**` 出发沿项目内 import 求传递闭包，
/// 闭包里（含自身）不得碰到 Flutter / Riverpod / `dart:io` / `dart:ui`，
/// 也不得触达任何 `domain/*/data/**`、`domain/*/application/**`。
///
/// 必须是传递的：模型只要有一条路径通到 Flutter，就没法在纯 Dart 环境复用，
/// 只查直接 import 会被「中间垫一个文件」绕过。
/// 每个 (模型, 违规目标) 只报一次，`hint` 里带最短传递链。
List<Violation> checkModelPurity(Map<String, List<String>> uris) {
  final violations = <Violation>[];

  for (final seed in uris.keys.where(_modelFile.hasMatch)) {
    // BFS：parent 同时充当 visited，用来还原传递链。
    final parent = <String, String?>{seed: null};
    final queue = <String>[seed];
    final reported = <String>{};

    String chainTo(String node, String target) {
      final chain = <String>[target];
      for (String? n = node; n != null; n = parent[n]) {
        chain.add(n);
      }
      return chain.reversed.join(' → ');
    }

    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      for (final uri in uris[node] ?? const <String>[]) {
        if (_isForbiddenExternal(uri)) {
          if (reported.add(uri)) {
            violations.add(
              Violation(
                seed,
                uri,
                _purityRule,
                '模型不能传递依赖 UI / 状态管理 / 平台库：${chainTo(node, uri)}',
              ),
            );
          }
          continue;
        }
        final reason = nonCanonicalUriReason(uri, from: node);
        if (reason != null) {
          // 无法可靠还原依赖边，传递闭包可能因此漏掉 Flutter / data：按违规处理。
          if (reported.add(uri)) {
            violations.add(
              Violation(
                seed,
                uri,
                _purityRule,
                '${_nonCanonicalUriHint(uri, reason)}，出现在 ${chainTo(node, uri)}',
              ),
            );
          }
          continue;
        }
        final path = projectPath(uri, from: node);
        if (path == null || parent.containsKey(path)) continue;
        if (_nonModelFile.hasMatch(path)) {
          // 到此为止：data/application 本身就是越界，其内部再引什么不重复报。
          parent[path] = node;
          if (reported.add(path)) {
            violations.add(
              Violation(
                seed,
                path,
                _purityRule,
                '模型不能触达 data / application：${chainTo(node, path)}',
              ),
            );
          }
          continue;
        }
        parent[path] = node;
        queue.add(path);
      }
    }
  }
  return violations;
}

/// 白名单里在代码中已不存在的边（棘轮：依赖消除后条目必须同步删除）。
List<AllowedEdge> staleEntries(
  Map<String, List<String>> uris,
  List<AllowedEdge> allowlist,
) {
  return [
    for (final e in allowlist)
      if (!(uris[e.from] ?? const <String>[]).any(
        (u) => projectPath(u, from: e.from) == e.to,
      ))
        e,
  ];
}

/// 白名单自身的合法性校验，返回问题描述；空列表表示合法。
///
/// 真实仓库测试与合成测试共用这个入口：上限在这里判定；「条目必须是
/// features → features」与 [checkLayering] 共用 [_illegalEntries]，不会各写一份。
/// [ceiling] 由调用方传入，保证测试可以用写死的数字验证，而不是拿常量自己比自己。
List<String> checkAllowlist(List<AllowedEdge> entries, {required int ceiling}) {
  final problems = <String>[];
  if (entries.length > ceiling) {
    problems.add('白名单只减不增：当前 ${entries.length} 条，上限 $ceiling');
  }
  for (final e in _illegalEntries(entries)) {
    problems.add(
      '$_illegalAllowRule：${e.from} → ${e.to}（只能是 features/<F> → features/<G>）',
    );
  }
  return problems;
}

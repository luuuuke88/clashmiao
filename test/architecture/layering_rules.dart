// 分层依赖规则：纯 Dart、无 flutter_test 依赖，输入是「文件 → 它的全部 URI」。
//
// 判定单位是「逻辑功能」而不是目录：同一个功能的文件可能散在 `domain/<x>/` 与
// `features/<x>/` 两处（旧布局），也可能已经归到 `features/<f>/<layer>/`（新布局），
// [logicalUnitOf] 两种都认，所以规则在目录搬迁前、中、后都成立。
//
// 功能分两档：
// - 能力型（[Tier.capability]）：config < profile < proxy < connection < backup，
//   见 [kCapabilityOrder]；顺序本身就是依赖方向；
// - 页面型（[Tier.page]）：home / settings / logs / about / assets / splash / options。
//
// 六条依赖规则：
// 1. 能力型的非页面层（model / data / application）只能依赖层级更低的能力型的
//    非页面层，以及 core；
// 2. 能力型的 presentation 可依赖任意能力型的非页面层、本功能的 presentation、
//    shared、core；
// 3. 页面型的任何一层可依赖任意能力型的任何一层；页面型之间不能互相依赖
//    （[kAllowlist] 里登记的跳转除外）；
// 4. 同一功能内部 presentation → application → data → model，不能反过来
//    （[checkIntraFeatureDirection]，历史欠账登记在 [kIntraDirectionDebt]）；
// 5. model 层纯净：不依赖 Flutter / Riverpod / dart:io / dart:ui，传递闭包里
//    也不触达 data / application（[checkModelPurity]）；
// 6. 页面只在 `app/` 里构造，跨功能的页面跳转只走 `AppRouteScope`：
//    `app/` 是唯一能依赖页面型功能的地方（规则 3 与白名单共同保证）。
//
// R2（只用 package 导入）已由 `always_use_package_imports` lint 把守，不重复实现。
import 'import_scanner.dart';

/// 功能的两档。
enum Tier { capability, page }

/// 能力型功能的固定先后顺序：只允许「后者依赖前者」。
/// 新增能力型功能必须在这里登记位置，否则判违规。
const kCapabilityOrder = ['config', 'profile', 'proxy', 'connection', 'backup'];

/// 页面型功能。
const kPageFeatures = {
  'home',
  'settings',
  'logs',
  'about',
  'assets',
  'splash',
  'options',
};

/// 功能内部的层，下标越大越靠上：只允许「上层依赖下层」（规则 4）。
const kLayers = ['model', 'data', 'application', 'presentation'];

/// 一个文件所属的逻辑功能与层。
class LogicalUnit {
  const LogicalUnit(this.feature, this.tier, this.layer);

  final String feature;
  final Tier tier;

  /// `model` / `data` / `application` / `presentation`。
  final String layer;

  bool get isPresentation => layer == 'presentation';

  @override
  String toString() => '$feature(${tier.name})/$layer';
}

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

/// 白名单条目：一条被豁免的「页面型 → 页面型」文件级依赖边（页面跳转）。
class AllowedEdge {
  const AllowedEdge(this.from, this.to, this.reason);

  final String from;
  final String to;
  final String reason;

  @override
  String toString() => '$from → $to（$reason）';
}

const _lintRule = '层间依赖';
const _intraRule = '同功能内部方向';
const _illegalAllowRule = '白名单条目非法';
const _purityRule = 'R1 模型纯净';
const _nonCanonicalUriRule = '非规范 URI';

final _backupFile = RegExp(r'^(backup_|restore_|startup_restore)');
const _optionsPageFile = 'config_options_page.dart';

/// 把 `lib/` 内相对路径归到逻辑功能；不属于任何功能返回 `null`。
///
/// 旧布局：
/// - `domain/<x>/<layer>/…`，其中 `routing` 就是 `proxy`；
/// - `features/<x>/<layer>/…`；其中 `features/config` 是三个功能混住，按文件拆：
///   文件名匹配 `^(backup_|restore_|startup_restore)`（含 `model/backup_bundle.dart`）
///   → `backup`；`config_options_page.dart` → `options`（页面型）；
///   其余（如 `dns_strategy_messages.dart`）→ `config`。
///
/// 新布局：`features/<f>/<layer>/…`，`<f>` 就是功能名。
///
/// 页面型功能的文件不在分层目录里（散文件、`widgets/` 之类的子目录）时按
/// presentation 处理。
///
/// 返回 `null` 的情形：`core` / `shared` / `app` / `main.dart`（不属于功能，走各自
/// 的规则），以及**无法归位**的路径——未登记的功能名、`domain/` 下的页面型功能名、
/// 能力型功能里不在分层目录中的文件。后一类由 [checkLayering] 报为违规，不会静默放过。
LogicalUnit? logicalUnitOf(String libPath) {
  final parts = libPath.split('/');
  if (parts.length < 3) return null;
  final root = parts[0];
  if (root != 'domain' && root != 'features') return null;

  var feature = parts[1];
  final file = parts.last;
  if (root == 'domain') {
    if (feature == 'routing') feature = 'proxy';
  } else if (feature == 'config') {
    if (_backupFile.hasMatch(file)) {
      feature = 'backup';
    } else if (file == _optionsPageFile) {
      feature = 'options';
    }
  }

  final Tier tier;
  if (kCapabilityOrder.contains(feature)) {
    tier = Tier.capability;
  } else if (root == 'features' && kPageFeatures.contains(feature)) {
    tier = Tier.page;
  } else {
    return null;
  }

  final layer = parts.length >= 4 && kLayers.contains(parts[2])
      ? parts[2]
      : (tier == Tier.page ? 'presentation' : null);
  if (layer == null) return null;
  return LogicalUnit(feature, tier, layer);
}

/// 一个文件在整体结构里的位置。
class _Place {
  const _Place(this.root, this.unit);

  /// `core` / `shared` / `app` / `main`，或 `domain` / `features`，
  /// 或 `unknown`（不在已知层里）。
  final String root;

  /// 仅 `domain` / `features` 且能归位时非空。
  final LogicalUnit? unit;

  bool get isFeatureRoot => root == 'domain' || root == 'features';

  bool get isUnrestricted => root == 'app' || root == 'main';

  /// `domain` / `features` 下无法归位的路径。
  bool get isUnplaced => isFeatureRoot && unit == null;

  static _Place of(String path) {
    if (path == 'main.dart') return const _Place('main', null);
    final root = path.split('/').first;
    switch (root) {
      case 'core':
      case 'shared':
      case 'app':
        return _Place(root, null);
      case 'domain':
      case 'features':
        return _Place(root, logicalUnitOf(path));
    }
    return const _Place('unknown', null);
  }
}

/// 白名单条目是否合法：两端都是页面型功能，且是不同的功能。
bool _isPageEdge(AllowedEdge e) {
  final from = logicalUnitOf(e.from);
  final to = logicalUnitOf(e.to);
  return from != null &&
      to != null &&
      from.tier == Tier.page &&
      to.tier == Tier.page &&
      from.feature != to.feature;
}

/// 白名单里不是「页面型 → 页面型」的非法条目。
/// [checkLayering]（逐条报违规）与 [checkAllowlist]（汇总问题）都从这里取，
/// 「什么算合法条目」只有这一份判定。
List<AllowedEdge> _illegalEntries(List<AllowedEdge> entries) => [
  for (final e in entries)
    if (!_isPageEdge(e)) e,
];

String _nonCanonicalUriHint(String uri, String reason) =>
    '非规范的 URI，请改用 package:clashmiao/ 导入（$reason）：$uri';

const _unplacedHint =
    '文件不在 core/shared/app/domain/features 的已登记位置里：能力型功能的文件必须放在 '
    'model/data/application/presentation 目录下，功能名必须登记在 kCapabilityOrder / '
    'kPageFeatures，请归位';

/// 层间依赖检查。[uris] 的键是 `lib/` 内相对路径，值是该文件的全部 URI。
///
/// 白名单**只**豁免「页面型 → 页面型」的页面跳转：跨层、跨能力的口子一旦能开，
/// 白名单就会变成架构的后门。所以不是页面型 → 页面型的条目本身就是违规。
///
/// 同一功能内部的层间方向（规则 4）不在这里判，见 [checkIntraFeatureDirection]。
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
        '白名单只能豁免页面型功能之间的页面跳转，其他层间依赖必须改代码',
      ),
    );
  }
  final allowed = {
    for (final e in allowlist)
      if (_isPageEdge(e)) '${e.from}\u0000${e.to}',
  };

  for (final entry in uris.entries) {
    final from = entry.key;
    final fromPlace = _Place.of(from);
    if (fromPlace.root == 'unknown' || fromPlace.isUnplaced) {
      violations.add(Violation(from, '-', _lintRule, _unplacedHint));
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
      if (fromPlace.isUnrestricted) continue;
      final to = projectPath(uri, from: from);
      if (to == null) continue;
      final toPlace = _Place.of(to);
      if (toPlace.root == 'unknown' || toPlace.isUnplaced) {
        violations.add(Violation(from, to, _lintRule, _unplacedHint));
        continue;
      }
      final hint = _check(fromPlace, toPlace);
      if (hint == null) continue;
      if (allowed.contains('$from\u0000$to')) continue;
      violations.add(Violation(from, to, _lintRule, hint));
    }
  }
  return violations;
}

/// 判定单条边；合规返回 `null`，违规返回修法提示。
String? _check(_Place from, _Place to) {
  switch (from.root) {
    case 'core':
      return to.root == 'core' ? null : 'core 只能依赖 core，不能向上依赖 ${to.root}';
    case 'shared':
      return (to.root == 'core' || to.root == 'shared')
          ? null
          : 'shared 只能依赖 core / shared，不能依赖 ${to.root}';
  }
  final f = from.unit!;
  switch (to.root) {
    case 'core':
      return null;
    case 'shared':
      return (f.tier == Tier.page || f.isPresentation)
          ? null
          : '${f.feature} 的 ${f.layer} 层不能依赖 shared：非页面层只能依赖 core 与更低的能力型功能';
    case 'app':
    case 'main':
      return '功能不能依赖 ${to.root}（app 层只能被入口使用）';
  }
  final t = to.unit!;
  if (f.feature == t.feature) return null; // 同功能内部的方向归规则 4

  if (f.tier == Tier.page) {
    return t.tier == Tier.capability
        ? null
        : '页面型功能之间不能互相依赖：页面跳转请通过 app 层的路由入口解耦';
  }
  if (t.tier == Tier.page) {
    return '能力型功能（${f.feature}）不能依赖页面型功能（${t.feature}）：'
        '页面只在 app 层构造，共享的部分请下沉到能力型功能或 shared';
  }
  if (f.isPresentation) {
    return t.isPresentation
        ? '能力型功能的 presentation 不能依赖其他能力型功能的 presentation'
              '（${f.feature} → ${t.feature}）：共享的 UI 请下沉到 shared'
        : null;
  }
  if (t.isPresentation) {
    return '${f.feature} 的 ${f.layer} 层不能依赖 ${t.feature} 的 presentation';
  }
  final fromIdx = kCapabilityOrder.indexOf(f.feature);
  final toIdx = kCapabilityOrder.indexOf(t.feature);
  return toIdx < fromIdx
      ? null
      : '能力型功能顺序为 ${kCapabilityOrder.join(' < ')}，'
            '${f.feature} 不能依赖更靠后的 ${t.feature}';
}

/// 规则 4：同一个逻辑功能内部，依赖方向只能是
/// presentation → application → data → model（可以跨层、可以同层，不能反过来）。
///
/// 非规范 URI、不认识的位置由 [checkLayering] 负责报，这里跳过。
List<Violation> checkIntraFeatureDirection(Map<String, List<String>> uris) {
  final violations = <Violation>[];
  for (final entry in uris.entries) {
    final from = entry.key;
    final f = logicalUnitOf(from);
    if (f == null) continue;
    for (final uri in entry.value) {
      if (nonCanonicalUriReason(uri, from: from) != null) continue;
      final to = projectPath(uri, from: from);
      if (to == null) continue;
      final t = logicalUnitOf(to);
      if (t == null || t.feature != f.feature) continue;
      if (kLayers.indexOf(f.layer) < kLayers.indexOf(t.layer)) {
        violations.add(
          Violation(
            from,
            to,
            _intraRule,
            '${f.feature} 内部依赖方向只能是 presentation → application → data → model，'
            '${f.layer} 不能依赖 ${t.layer}',
          ),
        );
      }
    }
  }
  return violations;
}

/// R1 里不允许模型（及其传递依赖）碰到的外部 URI。
bool _isForbiddenExternal(String uri) =>
    uri == 'dart:io' ||
    uri == 'dart:ui' ||
    uri.startsWith('package:flutter/') ||
    uri.startsWith('package:hooks_riverpod/') ||
    uri.startsWith('package:riverpod/') ||
    uri.startsWith('package:flutter_riverpod/');

bool _isModelFile(String path) => logicalUnitOf(path)?.layer == 'model';

bool _isNonModelFile(String path) {
  final layer = logicalUnitOf(path)?.layer;
  return layer == 'data' || layer == 'application';
}

/// R1 模型纯净：从任何功能（旧布局或新布局）的 model 层文件出发沿项目内 import 求传递闭包，
/// 闭包里（含自身）不得碰到 Flutter / Riverpod / `dart:io` / `dart:ui`，
/// 也不得触达任何功能的 data / application 层文件。
///
/// 必须是传递的：模型只要有一条路径通到 Flutter，就没法在纯 Dart 环境复用，
/// 只查直接 import 会被「中间垫一个文件」绕过。
/// 每个 (模型, 违规目标) 只报一次，`hint` 里带最短传递链。
List<Violation> checkModelPurity(Map<String, List<String>> uris) {
  final violations = <Violation>[];

  for (final seed in uris.keys.where(_isModelFile)) {
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
        if (_isNonModelFile(path)) {
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

/// 扣掉已登记欠账（[debt]，按 from + to 匹配）后剩下的违规。
List<Violation> withoutDebt(
  List<Violation> violations,
  List<AllowedEdge> debt,
) {
  final registered = {for (final e in debt) '${e.from}\u0000${e.to}'};
  return [
    for (final v in violations)
      if (!registered.contains('${v.from}\u0000${v.to}')) v,
  ];
}

/// 欠账里登记了、但代码中已不再违规的条目（棘轮：还清后必须同步删除）。
List<AllowedEdge> staleDebt(
  List<Violation> violations,
  List<AllowedEdge> debt,
) {
  final current = {for (final v in violations) '${v.from}\u0000${v.to}'};
  return [
    for (final e in debt)
      if (!current.contains('${e.from}\u0000${e.to}')) e,
  ];
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
/// 页面型 → 页面型」与 [checkLayering] 共用 [_illegalEntries]，不会各写一份。
/// [ceiling] 由调用方传入，保证测试可以用写死的数字验证，而不是拿常量自己比自己。
List<String> checkAllowlist(List<AllowedEdge> entries, {required int ceiling}) {
  final problems = <String>[];
  if (entries.length > ceiling) {
    problems.add('白名单只减不增：当前 ${entries.length} 条，上限 $ceiling');
  }
  for (final e in _illegalEntries(entries)) {
    problems.add('$_illegalAllowRule：${e.from} → ${e.to}（只能是页面型功能之间的页面跳转）');
  }
  return problems;
}

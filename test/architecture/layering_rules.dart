// 分层依赖规则：纯 Dart、无 flutter_test 依赖，输入是「文件 → 它的全部 URI」。
//
// 判定单位是「逻辑功能」：`features/<f>/<layer>/…` 里的 `<f>` 就是功能名，
// 见 [logicalUnitOf]。`lib/domain/` 已经不存在，出现在那里的任何文件都是违规。
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
// 3. 页面型的任何一层可依赖任意能力型的任何一层；页面型之间不能互相依赖；
// 4. 同一功能内部 presentation → application → data → model，不能反过来
//    （[checkIntraFeatureDirection]，无任何豁免）；
// 5. model 层纯净：不依赖 Flutter / Riverpod / dart:io / dart:ui，传递闭包里
//    也不触达 data / application（[checkModelPurity]）；
// 6. 页面只在 `app/` 里构造，跨功能的页面跳转只走 `AppRouteScope`：
//    `app/` 之外、页面所在功能之外的文件不得引用别的功能的 `*Page` 类
//    （[checkPageConstruction]）。
//
// 六条规则一律零豁免：没有白名单，也没有欠账登记。
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

const _lintRule = '层间依赖';
const _intraRule = '同功能内部方向';
const _pageRule = 'R6 页面只在 app 构造';
const _purityRule = 'R1 模型纯净';
const _nonCanonicalUriRule = '非规范 URI';

/// 把 `lib/` 内相对路径归到逻辑功能；不属于任何功能返回 `null`。
///
/// `features/<f>/<layer>/…`：`<f>` 就是功能名，不再按文件名拆分。
///
/// 页面型功能的文件不在分层目录里（散文件、`widgets/` 之类的子目录）时按
/// presentation 处理。
///
/// 返回 `null` 的情形：`core` / `shared` / `app` / `main.dart`（不属于功能，走各自
/// 的规则），以及**无法归位**的路径——未登记的功能名、能力型功能里不在分层目录中的
/// 文件、`lib/domain/` 下的一切。后一类由 [checkLayering] 报为违规，不会静默放过。
LogicalUnit? logicalUnitOf(String libPath) {
  final parts = libPath.split('/');
  if (parts.length < 3) return null;
  final root = parts[0];
  if (root != 'features') return null;

  final feature = parts[1];
  final Tier tier;
  if (kCapabilityOrder.contains(feature)) {
    tier = Tier.capability;
  } else if (kPageFeatures.contains(feature)) {
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

  /// `core` / `shared` / `app` / `main` / `features`，
  /// 或 `unknown`（不在已知层里，含已废弃的 `domain`）。
  final String root;

  /// 仅 `features` 且能归位时非空。
  final LogicalUnit? unit;

  bool get isFeatureRoot => root == 'features';

  bool get isUnrestricted => root == 'app' || root == 'main';

  /// `features` 下无法归位的路径。
  bool get isUnplaced => isFeatureRoot && unit == null;

  static _Place of(String path) {
    if (path == 'main.dart') return const _Place('main', null);
    final root = path.split('/').first;
    switch (root) {
      case 'core':
      case 'shared':
      case 'app':
        return _Place(root, null);
      case 'features':
        return _Place(root, logicalUnitOf(path));
    }
    return const _Place('unknown', null);
  }
}

String _nonCanonicalUriHint(String uri, String reason) =>
    '非规范的 URI，请改用 package:clashmiao/ 导入（$reason）：$uri';

const _unplacedHint =
    '文件不在 core/shared/app/features 的已登记位置里：能力型功能的文件必须放在 '
    'model/data/application/presentation 目录下，功能名必须登记在 kCapabilityOrder / '
    'kPageFeatures，请归位';

const _domainGoneHint =
    'lib/domain/ 已废弃，不允许再出现任何文件：能力型功能放进 '
    'features/<功能>/{model,data,application,presentation}/，不要重建 domain 目录';

/// 无法归位的路径对应的提示：`lib/domain/` 下的单独说明。
String _unplacedHintFor(String path) =>
    path.startsWith('domain/') ? _domainGoneHint : _unplacedHint;

/// 层间依赖检查。[uris] 的键是 `lib/` 内相对路径，值是该文件的全部 URI。
///
/// 零豁免：没有白名单，页面型功能之间的跳转一律走 `AppRouteScope`。
///
/// 同一功能内部的层间方向（规则 4）不在这里判，见 [checkIntraFeatureDirection]。
List<Violation> checkLayering(Map<String, List<String>> uris) {
  final violations = <Violation>[];

  for (final entry in uris.entries) {
    final from = entry.key;
    final fromPlace = _Place.of(from);
    if (fromPlace.root == 'unknown' || fromPlace.isUnplaced) {
      violations.add(Violation(from, '-', _lintRule, _unplacedHintFor(from)));
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
        violations.add(Violation(from, to, _lintRule, _unplacedHintFor(to)));
        continue;
      }
      final hint = _check(fromPlace, toPlace);
      if (hint == null) continue;
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
        : '页面型功能之间不能互相依赖：页面跳转请通过 AppRouteScope（app 层统一路由入口）解耦';
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

/// R1 模型纯净：从任何功能的 model 层文件出发沿项目内 import 求传递闭包，
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

/// 页面类：声明在某功能 presentation 层里、名字以 `Page` 结尾的公开类。
final _pageClass = RegExp(r'\bclass\s+([A-Z]\w*Page)\b');

final _blockComment = RegExp(r'/\*[\s\S]*?\*/');
final _lineComment = RegExp(r'(?<!:)//.*');

String _stripComments(String src) =>
    src.replaceAll(_blockComment, '').replaceAll(_lineComment, '');

/// 规则 6：页面只在 `app/` 里构造，跨功能的页面跳转只走 `AppRouteScope`。
///
/// [sources] 的键是 `lib/` 内相对路径，值是文件源码。页面类 = 声明在功能
/// presentation 层、名字以 `Page` 结尾的公开类。`app/` 以外、且不属于该页面所在
/// 逻辑功能的任何文件（含 `main.dart`、core、shared、其他功能）只要在代码里
/// （不含注释）出现这个类名，就是违规：构造它，或者拿它的类型做别的事，
/// 都意味着页面之间在互相持有。同一文件对同一页面只报一次，`to` 是页面类所在文件。
List<Violation> checkPageConstruction(Map<String, String> sources) {
  // 页面类名 → (所在文件, 所属功能)。
  final pages = <String, (String, String)>{};
  for (final e in sources.entries) {
    final unit = logicalUnitOf(e.key);
    if (unit == null || !unit.isPresentation) continue;
    for (final m in _pageClass.allMatches(_stripComments(e.value))) {
      pages.putIfAbsent(m.group(1)!, () => (e.key, unit.feature));
    }
  }
  if (pages.isEmpty) return const [];

  final violations = <Violation>[];
  for (final e in sources.entries) {
    if (e.key.startsWith('app/')) continue;
    final ownFeature = logicalUnitOf(e.key)?.feature;
    final code = _stripComments(e.value);
    for (final page in pages.entries) {
      final (pageFile, pageFeature) = page.value;
      if (pageFeature == ownFeature) continue;
      if (RegExp('\\b${page.key}\\b').hasMatch(code)) {
        violations.add(
          Violation(
            e.key,
            pageFile,
            _pageRule,
            '页面 ${page.key} 只能在 app/ 里构造；'
            '跨功能的页面跳转请通过 AppRouteScope',
          ),
        );
      }
    }
  }
  return violations;
}

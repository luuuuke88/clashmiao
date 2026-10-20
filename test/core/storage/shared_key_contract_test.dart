import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart 与原生（Android Kotlin）共享的偏好键契约。
///
/// 原生代码按 `flutter.<键>` 读 Dart 写进 `FlutterSharedPreferences` 的值。键名、
/// 类型、默认值、StringList 编码前缀任何一边改了、另一边没跟，原生会静默读到
/// 默认值（例如分应用代理名单读成空）。这里读取 Kotlin **源文本**做断言：
/// 两边不一致时测试红，而不是等真机上才发现。
const _constantsPath =
    'android/app/src/main/kotlin/com/clashmiao/clashmiao/core/Constants.kt';
const _prefsPath =
    'android/app/src/main/kotlin/com/clashmiao/clashmiao/core/Prefs.kt';

/// 内核协调器的持久化。旧版共享键（如 `started_by_user`）只在这里迁移时读一次，
/// 读法是 `kv.getXxx(LEGACY_NAME, <default>)`，`LEGACY_NAME = PrefsKey.NAME`。
const _kernelStorePath =
    'android/app/src/main/kotlin/com/clashmiao/clashmiao/engine/KernelStore.kt';

/// `object Name { const val X = "v" … }` → {Name.X: v}
Map<String, String> _kotlinStringConstants(String source) {
  final out = <String, String>{};
  final objects = RegExp(r'object (\w+) \{([^}]*)\}', dotAll: true);
  final consts = RegExp(r'const val (\w+) = "([^"$]*)"');
  for (final o in objects.allMatches(source)) {
    for (final c in consts.allMatches(o.group(2)!)) {
      out['${o.group(1)}.${c.group(1)}'] = c.group(2)!;
    }
  }
  return out;
}

/// `PrefsKey` 里 `const val NAME = "${FLUTTER}key"` → {NAME: key}
Map<String, String> _kotlinSharedKeys(String source) => {
  for (final m in RegExp(
    r'const val (\w+) = "\$\{FLUTTER\}([^"]+)"',
  ).allMatches(source))
    m.group(1)!: m.group(2)!,
};

/// `read(PrefsKey.NAME, <default>)` → `{NAME: <default 源码片段>}`
Map<String, String> _kotlinDefaults(String source) => {
  for (final m in RegExp(
    r'read\(PrefsKey\.(\w+),\s*([^)]+?)\)',
  ).allMatches(source))
    m.group(1)!: m.group(2)!.trim(),
};

/// KernelStore 里迁移读取的旧键：`kv.getXxx(LEGACY_A, <default>)` 且
/// `const val LEGACY_A = PrefsKey.NAME` → `{NAME: <default 源码片段>}`
Map<String, String> _kernelStoreLegacyDefaults(String source) {
  final alias = {
    for (final m in RegExp(
      r'const val (\w+) = PrefsKey\.(\w+)',
    ).allMatches(source))
      m.group(1)!: m.group(2)!,
  };
  return {
    for (final m in RegExp(
      r'kv\.get\w+\((\w+),\s*([^)]+?)\)',
    ).allMatches(source))
      ?alias[m.group(1)!]: m.group(2)!.trim(),
  };
}

Object _resolveDefault(String token, Map<String, String> objects) {
  if (token == 'true') return true;
  if (token == 'false') return false;
  if (token.startsWith('"') && token.endsWith('"')) {
    return token.substring(1, token.length - 1);
  }
  final resolved = objects[token];
  if (resolved != null) return resolved;
  fail('无法解析 Kotlin 默认值: $token');
}

void main() {
  late String constants;
  late String prefs;
  late Map<String, String> sharedKeys; // NAME → dart key
  late Map<String, String> objectConsts;
  late Map<String, String> defaults;

  setUpAll(() {
    final cFile = File(_constantsPath);
    final pFile = File(_prefsPath);
    expect(cFile.existsSync(), isTrue, reason: '找不到 $_constantsPath');
    expect(pFile.existsSync(), isTrue, reason: '找不到 $_prefsPath');
    constants = cFile.readAsStringSync();
    prefs = pFile.readAsStringSync();
    sharedKeys = _kotlinSharedKeys(constants);
    objectConsts = _kotlinStringConstants(constants);
    final kernelStore = File(_kernelStorePath);
    expect(kernelStore.existsSync(), isTrue, reason: '找不到 $_kernelStorePath');
    // Prefs.kt 的读取优先；KernelStore 只补那些已改为「迁移时读一次」的旧键。
    defaults = {
      ..._kernelStoreLegacyDefaults(kernelStore.readAsStringSync()),
      ..._kotlinDefaults(prefs),
    };
  });

  test('解析器自检：Kotlin 源里确实读到了这些键（防止解析出错让断言平凡通过）', () {
    expect(sharedKeys.length, greaterThanOrEqualTo(10));
    expect(sharedKeys['DYNAMIC_NOTIFICATION'], 'dynamic_notification');
    expect(defaults['DYNAMIC_NOTIFICATION'], 'true');
    expect(objectConsts['AppFilterMode.OFF'], 'off');
  });

  test('键名：Kotlin 的每个共享键都登记为原生共享，反之亦然', () {
    final kotlin = sharedKeys.values.toSet();
    final dart = PrefRegistry.nativeShared.map((s) => s.key).toSet();
    expect(
      kotlin.difference(dart),
      isEmpty,
      reason: 'Kotlin 里有、PrefRegistry 没登记（新增共享键必须两边同时登记）',
    );
    expect(
      dart.difference(kotlin),
      isEmpty,
      reason: 'PrefRegistry 里有、Kotlin 里没有',
    );
  });

  test('默认值与类型：Kotlin 读取时的默认值 = 登记表里的默认值', () {
    var checked = 0;
    for (final entry in sharedKeys.entries) {
      final spec = PrefRegistry.lookup(entry.value)!;
      final token = defaults[entry.key];
      if (spec.type == PrefType.stringList) continue; // 见下一个用例
      expect(
        token,
        isNotNull,
        reason: '${entry.value}：Prefs.kt 里没有 read(PrefsKey.${entry.key}, …)',
      );
      final kotlinDefault = _resolveDefault(token!, objectConsts);
      expect(
        kotlinDefault,
        spec.defaultValue,
        reason: '${entry.value} 的默认值两边不一致',
      );
      // 类型：Kotlin 的 read 重载由默认值字面量的类型决定。
      expect(
        PrefRegistry.matchesType(spec.type, kotlinDefault),
        isTrue,
        reason: '${entry.value} 的类型两边不一致',
      );
      checked++;
    }
    expect(checked, greaterThanOrEqualTo(8));
  });

  test('分应用代理：模式取值与名单键两边一致，名单缺省为空', () {
    // 模式取值：Kotlin 的 AppFilterMode 与 Dart 校验集合相同。
    final modes = {
      for (final e in objectConsts.entries)
        if (e.key.startsWith('AppFilterMode.')) e.value,
    };
    expect(modes, {'off', 'include', 'exclude'});
    for (final mode in modes) {
      expect(PrefRegistry.validate('per_app_proxy_mode', mode), PrefCheck.ok);
    }
    expect(
      PrefRegistry.validate('per_app_proxy_mode', 'all'),
      PrefCheck.outOfRange,
    );
    // 名单键：Kotlin 的 include / exclude 名单就是登记表里那两个 StringList。
    expect(sharedKeys['APP_FILTER_INCLUDE'], 'per_app_proxy_include_list');
    expect(sharedKeys['APP_FILTER_EXCLUDE'], 'per_app_proxy_exclude_list');
    for (final key in [
      'per_app_proxy_include_list',
      'per_app_proxy_exclude_list',
    ]) {
      final spec = PrefRegistry.lookup(key)!;
      expect(spec.type, PrefType.stringList);
      expect(spec.defaultValue, isEmpty);
    }
    // 缺省 / 没有前缀 → 空名单。
    expect(prefs, contains('val raw = read(key, "")'));
    expect(
      prefs,
      contains('if (!raw.startsWith(FLUTTER_LIST_MAGIC)) return emptyList()'),
    );
  });

  test(
    'StringList 编码前缀：Kotlin 解码器认的前缀 = Dart 常量 = shared_preferences 插件写入的前缀',
    () {
      final kotlinMagic = RegExp(
        r'private const val FLUTTER_LIST_MAGIC = "([^"]+)"',
      ).firstMatch(prefs)?.group(1);
      expect(
        kotlinMagic,
        isNotNull,
        reason: 'Prefs.kt 里找不到 FLUTTER_LIST_MAGIC',
      );
      expect(kotlinMagic, kFlutterStringListPrefix);
      expect(
        utf8.decode(base64.decode(kFlutterStringListPrefix)),
        'This is the prefix for a list.',
      );

      // 插件自己的常量（以 package_config 里实际解析到的版本为准）。
      final pluginSource = _installedPluginListPrefixSource();
      expect(
        pluginSource,
        contains('"$kFlutterStringListPrefix"'),
        reason: 'shared_preferences_android 的 LIST_PREFIX 变了，Kotlin 解码器要跟着改',
      );
    },
  );

  test('StringList 编码格式：Kotlin 解码器认得插件当前实际写入的格式（前缀 + "!" + JSON 列表）', () {
    // shared_preferences_android 2.3+ 写入 `<前缀>!<JSON 数组>`（插件的
    // JSON_LIST_PREFIX），而不是旧的 `<前缀><base64(Java 序列化)>`。Kotlin 解码器
    // 必须认得带 `!` 的 JSON 格式，否则分应用代理名单永远读成空。两种格式的实际
    // 解码由 Kotlin 侧 PrefsListDecoderTest 在 JVM 上覆盖。
    final kotlinMarker = RegExp(
      r'private const val JSON_LIST_MARKER = "([^"]+)"',
    ).firstMatch(prefs)?.group(1);
    expect(
      kotlinMarker,
      '!',
      reason: 'Prefs.AppFilter 里找不到 JSON 格式标记，或标记不是 "!"',
    );
    expect(
      prefs,
      contains('if (payload.startsWith(JSON_LIST_MARKER))'),
      reason: 'decodeFlutterList 必须按标记分流到 JSON 解码',
    );

    // 插件那边：JSON_LIST_PREFIX 就是 LIST_PREFIX 加同一个标记。
    final pluginJsonPrefix = _installedPluginLine('const val JSON_LIST_PREFIX');
    expect(pluginJsonPrefix, contains('"\$LIST_PREFIX$kotlinMarker"'));
  });
}

/// 当前依赖解析到的 shared_preferences_android 的 Kotlin 插件源码里，
/// 声明 `LIST_PREFIX` 的那一行。
String _installedPluginListPrefixSource() =>
    _installedPluginLine('const val LIST_PREFIX');

/// 当前依赖解析到的 shared_preferences_android 的 Kotlin 插件源码里，第一行
/// 包含 [needle] 的那一行。
String _installedPluginLine(String needle) {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final pkg = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == 'shared_preferences_android');
  final root = Directory.fromUri(Uri.parse(pkg['rootUri'] as String));
  final plugin = File(
    '${root.path}/android/src/main/kotlin/io/flutter/plugins/sharedpreferences/SharedPreferencesPlugin.kt',
  );
  expect(plugin.existsSync(), isTrue, reason: '找不到插件源码 ${plugin.path}');
  return plugin.readAsLinesSync().firstWhere((l) => l.contains(needle));
}

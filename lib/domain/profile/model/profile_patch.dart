import 'package:clashmiao/domain/config/model/advanced_config.dart';

/// 三态补丁字段：未指定 / 设置为某值 / 清除。
///
/// 用它而不是「null 表示不改」，是因为可空字段（自定义 UA、高级配置里的
/// 若干项）需要能区分「不动」与「清空」。
class Patch<T> {
  const Patch.unset() : _state = _PatchState.unset, _value = null;
  const Patch.set(T value) : _state = _PatchState.set, _value = value;
  const Patch.clear() : _state = _PatchState.clear, _value = null;

  final _PatchState _state;
  final T? _value;

  bool get isUnset => _state == _PatchState.unset;
  bool get isSet => _state == _PatchState.set;
  bool get isClear => _state == _PatchState.clear;

  /// 仅 [isSet] 时有意义。
  T get value => _value as T;

  /// 对一个可空字段应用补丁：unset → 原值，set → 新值，clear → null。
  T? resolve(T? current) {
    switch (_state) {
      case _PatchState.unset:
        return current;
      case _PatchState.set:
        return _value;
      case _PatchState.clear:
        return null;
    }
  }

  @override
  String toString() => switch (_state) {
    _PatchState.unset => 'Patch.unset',
    _PatchState.set => 'Patch.set($_value)',
    _PatchState.clear => 'Patch.clear',
  };
}

enum _PatchState { unset, set, clear }

/// [AdvancedConfig] 的字段级补丁：只改被指定的字段，其余（包括未知字段）保留。
class AdvancedConfigPatch {
  const AdvancedConfigPatch({
    this.remoteDnsOverride = const Patch.unset(),
    this.muxEnabled = const Patch.unset(),
    this.muxProtocol = const Patch.unset(),
    this.muxConcurrency = const Patch.unset(),
    this.fragmentEnabled = const Patch.unset(),
    this.fragmentRange = const Patch.unset(),
  });

  final Patch<String> remoteDnsOverride;
  final Patch<bool> muxEnabled;
  final Patch<String> muxProtocol;
  final Patch<int> muxConcurrency;
  final Patch<bool> fragmentEnabled;
  final Patch<String> fragmentRange;

  /// 合并到 [base] 上（base 为空时从默认值起算）。非空字段上的 `clear` 回落默认值。
  AdvancedConfig applyTo(AdvancedConfig? base) {
    final current = base ?? const AdvancedConfig();
    return AdvancedConfig(
      remoteDnsOverride: remoteDnsOverride.resolve(current.remoteDnsOverride),
      muxEnabled: muxEnabled.isSet ? muxEnabled.value : current.muxEnabled,
      muxProtocol: muxProtocol.isSet ? muxProtocol.value : current.muxProtocol,
      muxConcurrency: muxConcurrency.isSet
          ? muxConcurrency.value
          : current.muxConcurrency,
      fragmentEnabled: fragmentEnabled.isSet
          ? fragmentEnabled.value
          : current.fragmentEnabled,
      fragmentRange: fragmentRange.resolve(current.fragmentRange),
      extra: current.extra,
    );
  }
}

/// 订阅编辑补丁。每个字段独立三态，只触碰被指定的字段，
/// 因此不会把页面持有的旧快照写回去、覆盖刷新写入的 `lastUpdate` / `subInfo`。
///
/// `name` / `url` 的 `set` 会 trim，空白值被忽略（与旧 `editProfile` 一致）；
/// 对非空字段（name / url / updateInterval）`clear` 无意义，同样被忽略。
class ProfilePatch {
  const ProfilePatch({
    this.name = const Patch.unset(),
    this.url = const Patch.unset(),
    this.updateInterval = const Patch.unset(),
    this.customUserAgent = const Patch.unset(),
    this.advancedConfig = const Patch.unset(),
  });

  final Patch<String> name;
  final Patch<String> url;
  final Patch<Duration> updateInterval;
  final Patch<String> customUserAgent;

  /// set：以字段级补丁合并到现有高级配置；clear：整体移除高级配置。
  final Patch<AdvancedConfigPatch> advancedConfig;
}

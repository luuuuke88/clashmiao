import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';

/// 订阅存储相关的异常 → 给用户看的本地化文案；不属于这一类返回 null，
/// 由调用方用自己场景的兜底文案。
///
/// 目前只有一类需要专门提示：存储版本高于当前 App（用户降级运行）时订阅存储
/// 进入只读模式，任何会写订阅的入口都会收到 [StoreReadOnlyException]，
/// 统一提示「请升级 App 后再修改订阅」，而不是各自展示异常原文。
///
/// [translations] 是惰性取值：只有真的是只读异常时才会求值，避免普通失败路径
/// 为了一个用不上的文案去读 provider。
String? profileStoreErrorMessage(
  Object error,
  TranslationsEn Function() translations,
) => error is StoreReadOnlyException
    ? translations().failure.profiles.readOnlyUpgrade
    : null;

/// [error] 是否表示「刷新结果因订阅期间被改动而作废」。
///
/// 这是预期内的取消，不是失败：手动刷新、详情页、首页刷新应静默跳过（或按
/// 「订阅仍然存在」处理），不要弹「刷新失败」。
bool isStaleRefresh(Object error) => error is ProfileUpdateStaleException;

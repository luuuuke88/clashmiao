import 'package:shared_preferences/shared_preferences.dart';

/// 偏好存储的版本号：键名与当前代码支持的版本。
///
/// 缺失视为 0（旧版本数据）；高于 [kCurrentStorageSchema] 说明用户降级运行，
/// 此时订阅存储进入只读模式，避免旧代码把新格式数据改坏。
const kStorageSchemaKey = 'clashmiao_storage_schema';

/// 当前代码理解的最高存储版本。
const kCurrentStorageSchema = 1;

/// 读取当前存储版本：缺失、类型不符、负数一律按 0（旧版本数据）。读取永不抛出。
int readStorageSchema(SharedPreferences prefs) {
  try {
    final value = prefs.get(kStorageSchemaKey);
    return value is int && value > 0 ? value : 0;
  } catch (_) {
    return 0;
  }
}

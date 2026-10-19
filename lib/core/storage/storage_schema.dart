/// 偏好存储的版本号：键名与当前代码支持的版本。
///
/// 缺失视为 0（旧版本数据）；高于 [kCurrentStorageSchema] 说明用户降级运行，
/// 此时订阅存储进入只读模式，避免旧代码把新格式数据改坏。
const kStorageSchemaKey = 'clashmiao_storage_schema';

/// 当前代码理解的最高存储版本。
const kCurrentStorageSchema = 1;

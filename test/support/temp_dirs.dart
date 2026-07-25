import 'dart:io';

/// 尽力删除测试用的临时目录；删不掉就放过。
///
/// 直接 `await dir.delete(recursive: true)` 在机器负载高时会抛：
///
///     FileSystemException: Deletion failed, path = '.../details_save_XXXXXX'
///     (OS Error: Directory not empty, errno = 66)
///
/// 原因是被测代码的后台异步写入（例如"保存订阅 → 重新拉取 → 写配置文件"）
/// 落在了递归删除的**枚举**与实际 unlink 之间：删除时目录是空的，unlink 时
/// 又多了个文件。在满载的 12 核机器上跑全量测试可以稳定复现。
///
/// 关键点：**清理失败不该让测试失败**。断言全都通过了，只是临时目录没删干净
/// 就判失败，是纯粹的假阴性；而且它抛在 tearDown 里，堆栈跟被测逻辑毫无关系
/// （只有 `FileSystemEntity.delete`），最容易把排查引到错误方向——第一次遇到
/// 时我就先去怀疑了被测的保存逻辑。
///
/// 临时目录本来归系统回收，最坏结果是留下一个几 KB 的目录到下次重启。用
/// "重试几次 → 放弃"而不是"直接忽略"：真正只是竞态的话重试就成功了，日志
/// 干净；而如果哪天出现了别的删不掉的原因，也不会把测试搞红。
Future<void> deleteTempDirBestEffort(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      // 让在飞的写入先落地，再重试。
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

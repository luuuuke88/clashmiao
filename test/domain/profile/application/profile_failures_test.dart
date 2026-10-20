import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/domain/profile/application/profile_failures.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/data/subscription_fetch.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 订阅操作失败 → 类型化的本地化文案；异常原文绝不进文案。
void main() {
  final t = AppLocale.zhCn.buildSync();
  String msg(Object e) =>
      profileFailureMessage(e, t, failed: t.profile.update.failureMsg);
  DioException dio(DioExceptionType type) =>
      DioException(requestOptions: RequestOptions(), type: type);

  test('只读存储：直接给升级提示', () {
    expect(msg(const StoreReadOnlyException(9)), '请升级 App 后再修改订阅');
  });

  test('可识别的原因：操作失败文案 + 本地化原因', () {
    expect(msg(dio(DioExceptionType.connectionTimeout)), '更新配置文件失败：连接超时');
    expect(msg(TimeoutException('x')), '更新配置文件失败：连接超时');
    expect(msg(dio(DioExceptionType.badCertificate)), '更新配置文件失败：证书无效');
    expect(msg(dio(DioExceptionType.badResponse)), '更新配置文件失败：错误响应');
    expect(msg(dio(DioExceptionType.connectionError)), '更新配置文件失败：连接错误');
    expect(msg(const SocketException('refused')), '更新配置文件失败：连接错误');
    expect(
      msg(const ProfileValidationException('bad yaml at line 3')),
      '更新配置文件失败：无效配置',
    );
    expect(
      msg(
        const SubscriptionFetchException(
          reason: SubscriptionFetchFailure.noNodes,
          attemptedUserAgents: ['a'],
        ),
      ),
      '更新配置文件失败：无可用的线路',
    );
  });

  test('Parse 错误码映射：no-outbounds → 没有可用线路，其余码 → 无效配置', () {
    String fromParse(String err) =>
        msg(ProfileValidationException.fromParseError(err));
    expect(
      fromParse('no-outbounds: profile has no usable outbound'),
      '更新配置文件失败：无可用的线路',
    );
    for (final err in [
      'format-unknown: not a subscription',
      'uri-invalid: vless: bad uuid',
      'option-invalid: mixed-port',
      'build-failed: boom',
      'something else entirely',
      '',
    ]) {
      expect(fromParse(err), '更新配置文件失败：无效配置', reason: err);
    }
  });

  test('错误码取自消息前缀：认得的才取，原文不进文案', () {
    final known = ProfileValidationException.fromParseError(
      'no-outbounds: secret detail',
    );
    expect(known.code, 'no-outbounds');
    expect(msg(known), isNot(contains('secret')));
    expect(
      ProfileValidationException.fromParseError('uri-invalid: x').code,
      'uri-invalid',
    );
    expect(ProfileValidationException.fromParseError('weird: x').code, isNull);
    expect(ProfileValidationException.fromParseError('no colon').code, isNull);
    expect(ProfileValidationException.fromParseError(': x').code, isNull);
    expect(const ProfileValidationException('x').code, isNull);
  });

  test('认不出的异常：只给操作失败文案，不附原文', () {
    final m = msg(Exception('disk full at /data/x'));
    expect(m, '更新配置文件失败');
    expect(m, isNot(contains('disk')));
  });

  test('其它语言用各自的分隔符', () {
    final en = AppLocale.en.buildSync();
    expect(
      profileFailureMessage(
        dio(DioExceptionType.receiveTimeout),
        en,
        failed: en.profile.update.failureMsg,
      ),
      '${en.profile.update.failureMsg}: ${en.failure.connection.timeout}',
    );
  });
}

import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profiles_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profileDisplayPriority', () {
    test('激活的订阅优先级最高（0）', () {
      const profile = ProfileEntity(
        id: 'a',
        name: 'Active',
        url: 'https://example.com/a',
        active: true,
      );

      expect(profileDisplayPriority(profile), 0);
    });

    test('没有订阅信息的非激活订阅优先级居中（1）', () {
      const profile = ProfileEntity(
        id: 'b',
        name: 'Normal',
        url: 'https://example.com/b',
      );

      expect(profileDisplayPriority(profile), 1);
    });

    test('未过期且流量未耗尽的非激活订阅优先级居中（1）', () {
      final profile = ProfileEntity(
        id: 'c',
        name: 'Healthy',
        url: 'https://example.com/c',
        subInfo: SubscriptionInfo(
          upload: 100,
          download: 100,
          total: 1000,
          expire: DateTime.now().add(const Duration(days: 30)),
        ),
      );

      expect(profileDisplayPriority(profile), 1);
    });

    test('已过期的非激活订阅优先级最低（2）', () {
      final profile = ProfileEntity(
        id: 'd',
        name: 'Expired',
        url: 'https://example.com/d',
        subInfo: SubscriptionInfo(
          upload: 100,
          download: 100,
          total: 1000,
          expire: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      expect(profileDisplayPriority(profile), 2);
    });

    test('流量已耗尽（未过期）的非激活订阅优先级最低（2）', () {
      final profile = ProfileEntity(
        id: 'e',
        name: 'Exhausted',
        url: 'https://example.com/e',
        subInfo: SubscriptionInfo(
          upload: 600,
          download: 500,
          total: 1000,
          expire: DateTime.now().add(const Duration(days: 30)),
        ),
      );

      expect(profileDisplayPriority(profile), 2);
    });

    test('激活的订阅即使已过期也优先级最高（0）——激活状态优先于过期状态', () {
      final profile = ProfileEntity(
        id: 'f',
        name: 'ActiveButExpired',
        url: 'https://example.com/f',
        active: true,
        subInfo: SubscriptionInfo(
          upload: 100,
          download: 100,
          total: 1000,
          expire: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      expect(profileDisplayPriority(profile), 0);
    });
  });

  group('sortProfilesByPriority', () {
    test('激活排最前，已过期/已耗尽排最后，同优先级内按 tiebreaker 排序', () {
      const active = ProfileEntity(
        id: 'active',
        name: 'B-Active',
        url: 'https://example.com/active',
        active: true,
      );
      const normalA = ProfileEntity(
        id: 'normal-a',
        name: 'A-Normal',
        url: 'https://example.com/normal-a',
      );
      const normalZ = ProfileEntity(
        id: 'normal-z',
        name: 'Z-Normal',
        url: 'https://example.com/normal-z',
      );
      final expired = ProfileEntity(
        id: 'expired',
        name: 'A-Expired',
        url: 'https://example.com/expired',
        subInfo: SubscriptionInfo(
          upload: 0,
          download: 0,
          total: 1000,
          expire: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      // 打乱输入顺序，tiebreaker 按名称升序。
      final sorted = sortProfilesByPriority(
        [expired, normalZ, active, normalA],
        (a, b) => a.name.compareTo(b.name),
      );

      expect(sorted.map((p) => p.id).toList(), [
        'active',
        'normal-a',
        'normal-z',
        'expired',
      ]);
    });

    test('不改变入参列表（返回新列表）', () {
      final original = [
        const ProfileEntity(
          id: 'x',
          name: 'X',
          url: 'https://example.com/x',
        ),
        const ProfileEntity(
          id: 'y',
          name: 'Y',
          url: 'https://example.com/y',
          active: true,
        ),
      ];
      final originalOrder = original.map((p) => p.id).toList();

      sortProfilesByPriority(original, (a, b) => 0);

      expect(original.map((p) => p.id).toList(), originalOrder);
    });
  });
}

import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileEntity 存储格式', () {
    const entity = ProfileEntity(
      id: 'a',
      name: 'A',
      url: 'http://x',
      active: true,
      rev: 3,
      inc: 'deadbeefdeadbeef',
      extra: {'future': 1},
    );

    test('toJson 不写 active（激活只有一个真源），写 rev / inc / 未知字段', () {
      final json = entity.toJson();
      expect(json.containsKey('active'), isFalse);
      expect(json['rev'], 3);
      expect(json['inc'], 'deadbeefdeadbeef');
      expect(json['future'], 1);
    });

    test('inc 为空（旧数据）时不写出', () {
      expect(
        const ProfileEntity(
          id: 'a',
          name: 'A',
          url: 'x',
        ).toJson().containsKey('inc'),
        isFalse,
      );
    });

    test('fromJson 忽略旧的 active，缺 rev 读作 1，非法 rev 夹到 1', () {
      final e = ProfileEntity.fromJson({
        'id': 'a',
        'name': 'A',
        'url': 'x',
        'active': true,
      });
      expect(e.active, isFalse);
      expect(e.rev, 1);
      expect(
        ProfileEntity.fromJson({'id': 'a', 'name': 'A', 'url': 'x', 'rev': -4})
            .rev,
        1,
      );
    });

    test('往返：toJson → fromJson 保持 rev / inc / extra', () {
      final back = ProfileEntity.fromJson(entity.toJson());
      expect(back.rev, 3);
      expect(back.inc, 'deadbeefdeadbeef');
      expect(back.extra, {'future': 1});
      expect(back.toJson(), entity.toJson());
    });

    test('copyWith 保留 rev / inc / extra，可单独改', () {
      final c = entity.copyWith(name: 'B');
      expect(c.rev, 3);
      expect(c.inc, 'deadbeefdeadbeef');
      expect(c.extra, {'future': 1});
      expect(entity.copyWith(rev: 9).rev, 9);
    });

    test('rev 类型不对时 fromJson 抛（由 Store 隔离这一条）', () {
      expect(
        () => ProfileEntity.fromJson({
          'id': 'a',
          'name': 'A',
          'url': 'x',
          'rev': 'one',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });
}

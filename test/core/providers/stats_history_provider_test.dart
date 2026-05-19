import 'package:clashmiao/core/model/box_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const max = 60;

  BoxStats makeStat(int v) =>
      BoxStats(uplink: v, downlink: v, uplinkTotal: v, downlinkTotal: v);

  List<BoxStats> appendStat(List<BoxStats> acc, BoxStats s) {
    final updated = [...acc, s];
    return updated.length > max
        ? updated.sublist(updated.length - max)
        : updated;
  }

  group('StatsHistoryNotifier capping logic', () {
    test('caps at 60 samples', () {
      final samples = List.generate(70, makeStat);
      final result = samples.fold<List<BoxStats>>([], appendStat);

      expect(result.length, max);
      expect(result.first.uplink, 10);
      expect(result.last.uplink, 69);
    });

    test('retains all samples when under the cap', () {
      final samples = List.generate(10, makeStat);
      final result = samples.fold<List<BoxStats>>([], appendStat);
      expect(result.length, 10);
    });

    test('exactly at cap does not trim', () {
      final samples = List.generate(60, makeStat);
      final result = samples.fold<List<BoxStats>>([], appendStat);
      expect(result.length, max);
      expect(result.first.uplink, 0);
    });
  });
}

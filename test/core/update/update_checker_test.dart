import 'package:flutter_test/flutter_test.dart';

bool isNewerVersion(String latest, String current) {
  final l = latest.replaceFirst('v', '').split('.');
  final c = current.split('.');
  for (var i = 0; i < 3; i++) {
    final li = int.tryParse(i < l.length ? l[i] : '0') ?? 0;
    final ci = int.tryParse(i < c.length ? c[i] : '0') ?? 0;
    if (li > ci) return true;
    if (li < ci) return false;
  }
  return false;
}

void main() {
  test('newer version detected', () {
    expect(isNewerVersion('v1.2.0', '1.1.0'), isTrue);
  });

  test('same version not newer', () {
    expect(isNewerVersion('v1.1.0', '1.1.0'), isFalse);
  });

  test('older version not newer', () {
    expect(isNewerVersion('v1.0.9', '1.1.0'), isFalse);
  });

  test('patch bump detected', () {
    expect(isNewerVersion('v1.1.1', '1.1.0'), isTrue);
  });
}

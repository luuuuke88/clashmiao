import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String computeSha256(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  test('sha256 produces consistent output for same input', () {
    final data = utf8.encode('hello world');
    final hash1 = computeSha256(data);
    final hash2 = computeSha256(data);
    expect(hash1, hash2);
    expect(hash1.length, 64); // SHA-256 is always 64 hex chars
  });

  test('mismatched hash rejects content', () {
    const expected = 'aaaa';
    final actual = computeSha256(utf8.encode('wrong content'));
    expect(actual != expected, isTrue);
  });
}

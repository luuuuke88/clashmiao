import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> buildProfileJson({
  String id = 'test-id',
  String? notes,
  String? customUserAgent,
  int updateIntervalHours = 24,
}) {
  return {
    'id': id,
    'name': 'Test',
    'url': 'https://example.com',
    'active': false,
    'updateInterval': updateIntervalHours,
    if (notes != null) 'notes': notes,
    if (customUserAgent != null) 'customUserAgent': customUserAgent,
  };
}

void main() {
  test('new fields default to null for old profiles', () {
    final json = buildProfileJson();
    final notes = json['notes'] as String?;
    final ua = json['customUserAgent'] as String?;
    expect(notes, isNull);
    expect(ua, isNull);
  });

  test('new fields round-trip through JSON', () {
    final json = buildProfileJson(
      notes: 'test note',
      customUserAgent: 'MyApp/1.0',
    );
    expect(json['notes'], 'test note');
    expect(json['customUserAgent'], 'MyApp/1.0');
  });

  test('updateInterval defaults to 24h', () {
    final json = buildProfileJson();
    final hours = json['updateInterval'] as int;
    expect(hours, 24);
  });
}

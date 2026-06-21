import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getDefaultConfigOptions', () {
    test('smart mode emits database-free CN suffix bypass rules', () {
      final options = getDefaultConfigOptions(executeConfigAsIs: false);

      expect(options['execute-config-as-is'], isFalse);
      expect(options['region'], 'other');
      expect(options['direct-dns-address'], '223.5.5.5');
      expect(options['enable-dns-routing'], isTrue);

      final rules = (options['rules'] as List).cast<Map<String, dynamic>>();
      expect(rules, hasLength(1));
      expect(rules.single['domains'], 'domain:.cn');
      expect(rules.single['ip'], '');
      expect(rules.single['outbound'], 'bypass');
    });

    test('global mode keeps bypass rules disabled', () {
      final options = getDefaultConfigOptions(executeConfigAsIs: true);

      expect(options['execute-config-as-is'], isTrue);
      expect(options['direct-dns-address'], '1.1.1.1');
      expect(options['rules'], isEmpty);
    });
  });
}

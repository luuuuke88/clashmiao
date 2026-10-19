import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/agreement_modal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return container;
}

Widget _host(ProviderContainer container, void Function(bool?) onResult) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                onResult(
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => AgreementModal(
                      title: '服务条款',
                      body: TextSpan(
                        children: [
                          const TextSpan(text: '继续即表示同意'),
                          linkTextSpan(
                            '条款',
                            Uri.parse('https://example.com/t'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open-agreement'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('AgreementModal renders title, body and both buttons', (
    tester,
  ) async {
    final container = await _container();
    addTearDown(container.dispose);
    final t = container.read(translationsProvider);

    await tester.pumpWidget(_host(container, (_) {}));
    await tester.tap(find.text('open-agreement'));
    await tester.pumpAndSettle();

    expect(find.text('服务条款'), findsOneWidget);
    expect(find.textContaining('继续即表示同意', findRichText: true), findsOneWidget);
    expect(find.text(t.general.decline), findsOneWidget);
    expect(find.text(t.general.agree), findsOneWidget);
  });

  testWidgets('tapping agree pops true', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    final t = container.read(translationsProvider);
    bool? result;

    await tester.pumpWidget(_host(container, (v) => result = v));
    await tester.tap(find.text('open-agreement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.general.agree));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('tapping decline pops false', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    final t = container.read(translationsProvider);
    bool? result;

    await tester.pumpWidget(_host(container, (v) => result = v));
    await tester.tap(find.text('open-agreement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.general.decline));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  test('linkTextSpan is blue and tappable', () {
    final span = linkTextSpan('条款', Uri.parse('https://example.com/t'));
    expect(span.text, '条款');
    expect(span.style?.color, Colors.blue);
    expect(span.recognizer, isA<TapGestureRecognizer>());
    expect((span.recognizer! as TapGestureRecognizer).onTap, isNotNull);
  });
}

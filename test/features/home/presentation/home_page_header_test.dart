import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';

import '../../../support/known_overflow.dart';

/// 首页页头（标题 + 两颗圆按钮）在 320 dp、文字 1.0x / 2.0x、LTR / RTL 下的布局
/// 断言。只读页头，不碰连接区。
///
/// 页头本身必须**不溢出**：标题在 [PageHeader] 里是 Expanded（可折成两行再省略），
/// 按钮永远排在屏内。
///
/// ## 已知溢出（精确捕获，不是笼统吞掉）
///
/// 2.0x 时连接区另有两处溢出（连接按钮的竖向 Column、模式分段控件的横向 Row），
/// 属于连接区（正在被重写、本任务不得触碰），见 `test/support/known_overflow.dart`：
/// 按创建者链前缀（具体的 RenderFlex 位置）、溢出边（bottom / right）与量级范围
/// 精确匹配，且每项在一个场景里**恰好一次**。其它任何溢出（包括页头自己的）、
/// 已知项的第二次出现、位置 / 边 / 量级对不上的溢出一律原样交给框架，让测试失败。
///
/// 连接区的已知项被修掉之后，对应的期望会失败——到时候删掉那一项即可，不要放宽过滤。

const _profile = ProfileEntity(
  id: 'p1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

Future<Widget> _host(TextDirection direction) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      activeProfileProvider.overrideWith((_) => Future.value(_profile)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: const HomePage(),
      ),
    ),
  );
}

void main() {
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320 dp、文字 $scale 倍、${direction.name.toUpperCase()}：'
          '首页页头不溢出、按钮与标题垂直居中，连接区已知溢出被精确捕获', (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final host = await _host(direction);
        // 只放行连接区的已知溢出（按创建者位置 + 溢出边 + 量级精确匹配），
        // 每项在一个场景里恰好一次；页头自己的溢出、任何其它溢出、已知项的
        // 第二次出现，都会原样交给框架让测试失败。
        final expected = <KnownOverflow>[
          if (scale == 2.0) ...[connectionButtonOverflow, modeSelectorOverflow],
        ];
        final seen = await runAllowingKnownOverflows(expected, () async {
          await tester.pumpWidget(host);
          await tester.pump(const Duration(milliseconds: 250));
        });
        expect(
          seen,
          unorderedEquals(expected.map((k) => k.name)),
          reason: '连接区已知溢出应各出现恰好一次',
        );

        final header = find.byType(DragToMoveArea);
        expect(header, findsOneWidget);
        final title = find.descendant(
          of: header,
          matching: find.text('ClashMiao'),
        );
        expect(title, findsOneWidget);
        // 版本号已删：页头里除标题外没有别的文字。
        expect(
          find.descendant(of: header, matching: find.byType(Text)),
          findsOneWidget,
        );
        final titleRect = tester.getRect(title);
        final blockCenter = titleRect.center.dy;

        final buttons = find.descendant(
          of: header,
          matching: find.byType(GlassIconButton),
        );
        expect(buttons, findsNWidgets(2));
        final rects = [
          for (var i = 0; i < 2; i++) tester.getRect(buttons.at(i)),
        ];
        for (var i = 0; i < 2; i++) {
          expect(rects[i].height, greaterThanOrEqualTo(48));
          expect(
            (rects[i].center.dy - blockCenter).abs(),
            lessThanOrEqualTo(0.5),
            reason: '第 ${i + 1} 颗按钮应与标题块垂直居中',
          );
        }

        // 方向感知的几何：沿「起点 → 末端」依次是 标题块、按钮 1、按钮 2。
        final block = titleRect;
        final ltr = direction == TextDirection.ltr;
        bool before(Rect a, Rect b) =>
            ltr ? a.right <= b.left + 0.5 : a.left >= b.right - 0.5;
        expect(before(block, rects[0]), isTrue, reason: '标题块不应压到第 1 颗按钮');
        expect(before(rects[0], rects[1]), isTrue, reason: '两颗按钮不应重叠');

        // 屏内：所有元素都落在页头内容区（屏宽两侧各留 24 dp 页边距）里，
        // 不再有任何越界量。
        const screenWidth = 320.0;
        const pagePadding = 24.0;
        for (final r in [block, ...rects]) {
          expect(r.left, greaterThanOrEqualTo(pagePadding - 0.5));
          expect(r.right, lessThanOrEqualTo(screenWidth - pagePadding + 0.5));
        }

        // 页头与线路页同一个 PageHeader：最小高度 48 dp。
        final headerRect = tester.getRect(header);
        expect(headerRect.height, greaterThanOrEqualTo(48));

        // 两颗圆按钮的提示文字来自 i18n（简中）。
        expect(find.byTooltip('快速设置'), findsOneWidget);
        expect(find.byTooltip('新的配置文件'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

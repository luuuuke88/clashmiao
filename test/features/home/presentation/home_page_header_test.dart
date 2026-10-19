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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';

/// 首页页头（标题块 + 两颗圆按钮）在 320 dp、文字 1.0x / 2.0x、LTR / RTL 下的
/// 布局断言。只读页头，不碰连接区。
///
/// ## 已知溢出（精确捕获，不是笼统吞掉）
///
/// - 首页页头那一行（创建者链含 `DragToMoveArea`）在 320 dp 下横向溢出：flutter_test
///   默认的 Ahem 字体比真机宽，1.0x 就会溢出；2.0x 真机上也必然出现（28 sp 标题
///   放大一倍已超过按钮之外的剩余宽度）。属于首页页头与文字缩放的后续任务，
///   这里不修，只**精确断言它存在**，并且按溢出量校验几何位置。
/// - 2.0x 时连接区另有两处溢出（创建者链含 `ConnectionButton`、`_ModeSelector`），
///   属于连接区（正在被重写、本任务不得触碰），同样列为已知项逐一断言。
/// - 其它任何溢出一律让测试失败：未知溢出会原样转交给框架的错误处理。
///
/// 已知项被修掉之后，对应的期望会失败——到时候删掉那一项即可，不要放宽过滤。

const _profile = ProfileEntity(
  id: 'p1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

Future<Widget> _host(TextDirection direction) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
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

/// 一次溢出报告：归类（按创建者链）、溢出量、框架报告的溢出边。
class _Overflow {
  _Overflow(this.kind, this.amount, this.side);

  final String kind;
  final double amount;
  final String side;
}

/// 按 RenderFlex 的创建者链识别溢出属于哪一块；不认识的返回 null。
String? _classify(String creatorChain) {
  if (creatorChain.contains('DragToMoveArea')) return 'header';
  if (creatorChain.contains('ConnectionButton')) return 'connectionButton';
  if (creatorChain.contains('_ModeSelector')) return 'modeSelector';
  return null;
}

void main() {
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320 dp、文字 $scale 倍、${direction.name.toUpperCase()}：'
          '首页页头按钮与标题块垂直居中，已知溢出被精确捕获', (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final host = await _host(direction);
        final previousHandler = FlutterError.onError;
        final overflows = <_Overflow>[];
        FlutterError.onError = (details) {
          final message = details.exceptionAsString();
          final match = RegExp(
            r'overflowed by ([\d.]+) pixels on the (\w+)',
          ).firstMatch(message);
          if (match != null) {
            final chain = (details.informationCollector?.call() ?? const [])
                .map((n) => n.toStringDeep())
                .join('\n');
            final kind = _classify(chain);
            if (kind != null) {
              overflows.add(
                _Overflow(kind, double.parse(match.group(1)!), match.group(2)!),
              );
              return;
            }
          }
          // 不认识的溢出（或任何其它错误）原样交给框架，让测试失败。
          previousHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousHandler);

        await tester.pumpWidget(host);
        await tester.pump(const Duration(milliseconds: 250));
        FlutterError.onError = previousHandler;

        // 已知溢出：恰好这几类，一类不多、一类不少。
        final expectedKinds = <String>{
          'header',
          if (scale == 2.0) ...['connectionButton', 'modeSelector'],
        };
        expect(
          overflows.map((o) => o.kind).toSet(),
          expectedKinds,
          reason: '出现了与预期不同的溢出集合',
        );
        final headerOverflow = overflows.firstWhere((o) => o.kind == 'header');
        expect(headerOverflow.amount, greaterThan(0));
        final header = find.byType(DragToMoveArea);
        expect(header, findsOneWidget);
        final title = find.descendant(
          of: header,
          matching: find.text('ClashMiao'),
        );
        expect(title, findsOneWidget);
        // 标题块：标题 Text 最近的那个 Column（标题 + 其下的小字）。
        final titleBlock = find
            .ancestor(of: title, matching: find.byType(Column))
            .first;
        final blockCenter = tester.getCenter(titleBlock).dy;

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
        final block = tester.getRect(titleBlock);
        final ltr = direction == TextDirection.ltr;
        bool before(Rect a, Rect b) =>
            ltr ? a.right <= b.left + 0.5 : a.left >= b.right - 0.5;
        expect(before(block, rects[0]), isTrue, reason: '标题块不应压到第 1 颗按钮');
        expect(before(rects[0], rects[1]), isTrue, reason: '两颗按钮不应重叠');

        // 屏内：所有元素的左缘不得出屏。右缘可以超出页头内容区（屏宽减去
        // 24 dp 页边距）的量不得大于上面捕获的已知溢出量。框架在两种方向下
        // 都把溢出报在物理右侧——LTR 时是末端的按钮越界，RTL 时是起点的标题块
        // 越界（Row 的子项整体从左边缘 24 dp 处排起），所以这里按物理边界比较，
        // 先后顺序则用上面方向感知的 before() 断言。
        const screenWidth = 320.0;
        const pagePadding = 24.0;
        final rightLimit = screenWidth - pagePadding + headerOverflow.amount;
        for (final r in [block, ...rects]) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(rightLimit + 0.5));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

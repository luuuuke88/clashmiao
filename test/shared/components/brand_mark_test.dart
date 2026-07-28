import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('两种品牌图变体映射到统一资产', (tester) async {
    Future<String> assetFor(BrandMarkVariant variant) async {
      await tester.pumpWidget(
        MaterialApp(home: BrandMark(size: 96, variant: variant)),
      );
      final image = tester.widget<Image>(find.byType(Image));
      return (image.image as AssetImage).assetName;
    }

    expect(
      await assetFor(BrandMarkVariant.tile),
      'assets/images/brand_logo.png',
    );
    expect(
      await assetFor(BrandMarkVariant.transparent),
      'assets/images/brand_mark.png',
    );
  });
}

import 'package:flutter/material.dart';

enum BrandMarkVariant { tile, transparent }

class BrandMark extends StatelessWidget {
  const BrandMark({
    required this.size,
    this.variant = BrandMarkVariant.tile,
    super.key,
  });

  final double size;
  final BrandMarkVariant variant;

  String get _asset => switch (variant) {
    BrandMarkVariant.tile => 'assets/images/brand_logo.png',
    BrandMarkVariant.transparent => 'assets/images/brand_mark.png',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ClashMiao',
      image: true,
      child: Image.asset(
        _asset,
        key: ValueKey('brand-mark-${variant.name}'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

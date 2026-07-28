import 'package:flutter/material.dart';

/// Speed Cat 的品牌色，取自 `assets/images/brand_logo.png` 那块图钉底色的渐变
/// 两端。全局主题的种子色、代码里画出来的品牌图形都从这里取——否则同一个界面
/// 上会出现好几种"品牌蓝"，而且没有一种跟 App 图标是同一个蓝。
abstract final class BrandColors {
  static const Color indigo = Color(0xFF6A64F8);
  static const Color indigoDeep = Color(0xFF3956DC);

  /// 猫脸上那道闪电的黄，品牌里唯一的暖色。
  static const Color gold = Color(0xFFFCD13C);

  /// 未连接（休眠）时的品牌蓝：色相不动、饱和度收掉、亮度提上去。
  ///
  /// 还是那只猫，但整体从"通电"退回"待机"——满饱和的靛蓝在没连上的时候会读成
  /// "一切正常"，跟屏幕上写着的"还没有线路喵"互相矛盾。
  static const Color indigoIdle = Color(0xFFB5B5D9);
  static const Color indigoIdleDeep = Color(0xFF8E90C2);
}

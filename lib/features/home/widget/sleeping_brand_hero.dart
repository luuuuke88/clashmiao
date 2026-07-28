import 'package:clashmiao/features/home/widget/sleeping_cat_aura.dart';
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:clashmiao/shared/components/frosted_disc.dart';
import 'package:flutter/material.dart';

/// 空态中央的品牌图形：磨砂玻璃圆盘 + 白色 Speed Cat 标记，猫在睡觉。
///
/// 圆盘不是装饰而是**可见性**：`brand_mark.png` 是一只白猫，直接摆在浅色主题
/// 的页面底色上等于白底白猫，只剩下一道黄色闪电。
///
/// 睡觉的动效（呼吸、z、柔光）全部来自 [SleepingCatAura]——首页那颗未连接的
/// 连接按钮用的是同一个组件，两处画的是同一只猫，休眠时就该长得一模一样。
class SleepingBrandHero extends StatelessWidget {
  const SleepingBrandHero({super.key});

  @override
  Widget build(BuildContext context) {
    return const SleepingCatAura(
      discSize: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FrostedDisc(key: ValueKey('empty_brand_disc'), size: 132),
          // 标记图自带留白（猫头只占画布的 53%），所以尺寸比圆盘大一圈才是
          // 视觉上"填满六成"的比例。
          BrandMark(size: 150, variant: BrandMarkVariant.transparent),
        ],
      ),
    );
  }
}

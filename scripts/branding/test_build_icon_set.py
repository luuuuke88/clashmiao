#!/usr/bin/env python3

from __future__ import annotations

import unittest

from PIL import Image

import build_icon_set


class RefinedMarkTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = Image.open(build_icon_set.SOURCE_MARK_PATH).convert("RGBA")
        cls.refined = build_icon_set.build_refined_mark(cls.source)
        cls.source_main = build_icon_set.color_class_mask(
            cls.source,
            build_icon_set.WHITE,
        )
        cls.refined_main = build_icon_set.color_class_mask(
            cls.refined,
            build_icon_set.WHITE,
        )
        cls.source_bolt = build_icon_set.color_class_mask(
            cls.source,
            build_icon_set.YELLOW,
        )
        cls.refined_bolt = build_icon_set.color_class_mask(
            cls.refined,
            build_icon_set.YELLOW,
        )

    def test_refinement_preserves_canvas_and_transparency(self) -> None:
        self.assertEqual(self.refined.size, (1024, 1024))
        self.assertEqual(self.refined.mode, "RGBA")
        self.assertEqual(self.refined.getpixel((0, 0))[3], 0)

    def test_refinement_keeps_cat_and_lightning_pixels(self) -> None:
        source_main_box = self.source_main.getbbox()
        refined_main_box = self.refined_main.getbbox()
        source_bolt_box = self.source_bolt.getbbox()
        refined_bolt_box = self.refined_bolt.getbbox()
        self.assertIsNotNone(source_main_box)
        self.assertIsNotNone(refined_main_box)
        self.assertIsNotNone(source_bolt_box)
        self.assertIsNotNone(refined_bolt_box)
        assert source_main_box is not None
        assert refined_main_box is not None
        assert source_bolt_box is not None
        assert refined_bolt_box is not None
        self.assertEqual(
            (
                source_main_box[2] - source_main_box[0],
                source_main_box[3] - source_main_box[1],
            ),
            (
                refined_main_box[2] - refined_main_box[0],
                refined_main_box[3] - refined_main_box[1],
            ),
        )
        self.assertEqual(
            (
                source_bolt_box[2] - source_bolt_box[0],
                source_bolt_box[3] - source_bolt_box[1],
            ),
            (
                refined_bolt_box[2] - refined_bolt_box[0],
                refined_bolt_box[3] - refined_bolt_box[1],
            ),
        )

    def test_refinement_centers_cat_head_horizontally(self) -> None:
        cat_box = self.refined_main.getbbox()

        self.assertIsNotNone(cat_box)
        assert cat_box is not None
        cat_center_x = (cat_box[0] + cat_box[2]) / 2
        self.assertLessEqual(abs(cat_center_x - 512), 1)

    def test_refinement_removes_all_trail_pixels(self) -> None:
        trail = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.TRAIL,
        )

        self.assertIsNone(trail.getbbox())
        self.assertEqual(
            build_icon_set.connected_component_count(trail),
            0,
        )

    def test_brand_layers_split_cat_and_bolt_without_moving_them(self) -> None:
        cat = build_icon_set.build_brand_layer(
            self.refined,
            build_icon_set.WHITE,
        )
        bolt = build_icon_set.build_brand_layer(
            self.refined,
            build_icon_set.YELLOW,
        )

        self.assertEqual(cat.mode, "RGBA")
        self.assertEqual(bolt.mode, "RGBA")
        self.assertEqual(cat.getpixel((0, 0))[3], 0)
        self.assertEqual(bolt.getpixel((0, 0))[3], 0)
        self.assertEqual(
            cat.getchannel("A").getbbox(),
            self.refined_main.getbbox(),
        )
        self.assertEqual(
            bolt.getchannel("A").getbbox(),
            self.refined_bolt.getbbox(),
        )


if __name__ == "__main__":
    unittest.main()

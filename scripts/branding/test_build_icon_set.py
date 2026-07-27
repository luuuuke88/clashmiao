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

    def test_refinement_preserves_canvas_and_transparency(self) -> None:
        self.assertEqual(self.refined.size, (1024, 1024))
        self.assertEqual(self.refined.mode, "RGBA")
        self.assertEqual(self.refined.getpixel((0, 0))[3], 0)

    def test_refinement_keeps_cat_and_lightning_pixels(self) -> None:
        source_main = build_icon_set.color_class_mask(
            self.source,
            build_icon_set.WHITE,
        )
        refined_main = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.WHITE,
        )

        source_bolt = build_icon_set.color_class_mask(
            self.source,
            build_icon_set.YELLOW,
        )
        refined_bolt = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.YELLOW,
        )
        source_main_box = source_main.getbbox()
        refined_main_box = refined_main.getbbox()
        source_bolt_box = source_bolt.getbbox()
        refined_bolt_box = refined_bolt.getbbox()
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
        cat_box = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.WHITE,
        ).getbbox()

        self.assertIsNotNone(cat_box)
        assert cat_box is not None
        cat_center_x = (cat_box[0] + cat_box[2]) / 2
        self.assertLessEqual(abs(cat_center_x - 512), 1)

    def test_refinement_replaces_two_lines_with_one_detached_wave(self) -> None:
        wave = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.TRAIL,
        )
        wave_box = wave.getbbox()
        white_box = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.WHITE,
        ).getbbox()

        self.assertIsNotNone(wave_box)
        self.assertIsNotNone(white_box)
        assert wave_box is not None
        assert white_box is not None
        self.assertEqual(build_icon_set.connected_component_count(wave), 1)
        self.assertGreaterEqual(wave_box[0], 90)
        self.assertLessEqual(wave_box[2], 270)
        self.assertGreaterEqual(white_box[0] - wave_box[2], 20)
        self.assertLessEqual(wave_box[2] - wave_box[0], 120)
        self.assertLessEqual(wave_box[3] - wave_box[1], 65)


if __name__ == "__main__":
    unittest.main()

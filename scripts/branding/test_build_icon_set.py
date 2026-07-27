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
        self.assertEqual(source_main.getbbox(), refined_main.getbbox())

        source_bolt = build_icon_set.color_class_mask(
            self.source,
            build_icon_set.YELLOW,
        )
        refined_bolt = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.YELLOW,
        )
        self.assertEqual(source_bolt.getbbox(), refined_bolt.getbbox())

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
        self.assertGreaterEqual(white_box[0] - wave_box[2], 8)
        self.assertLessEqual(wave_box[3] - wave_box[1], 100)


if __name__ == "__main__":
    unittest.main()

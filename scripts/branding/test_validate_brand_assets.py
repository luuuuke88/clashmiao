#!/usr/bin/env python3

from __future__ import annotations

import unittest

from PIL import Image, ImageDraw

import build_icon_set
import validate_brand_assets


class BrandGeometryValidationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = Image.open(build_icon_set.SOURCE_MARK_PATH).convert("RGBA")
        cls.refined = build_icon_set.build_refined_mark(source)
        cls.cat = build_icon_set.build_brand_layer(
            cls.refined,
            build_icon_set.WHITE,
        )

    def test_source_with_trails_is_rejected(self) -> None:
        source = Image.open(build_icon_set.SOURCE_MARK_PATH).convert("RGBA")

        errors = validate_brand_assets.brand_mark_geometry_errors(source)

        self.assertIn("brand mark must not contain trail pixels", errors)

    def test_tailless_refined_mark_is_accepted(self) -> None:
        refined = Image.open(build_icon_set.MARK_PATH).convert("RGBA")

        errors = validate_brand_assets.brand_mark_geometry_errors(refined)

        self.assertEqual(errors, [])

    def test_small_cat_coverage_is_rejected(self) -> None:
        icon = Image.new("RGBA", (1024, 1024))
        ImageDraw.Draw(icon).rectangle(
            (312, 250, 711, 774),
            fill=(*build_icon_set.WHITE, 255),
        )

        errors = validate_brand_assets.brand_logo_geometry_errors(icon)

        self.assertIn("brand logo cat width outside B range: 400", errors)

    def test_off_center_cat_is_rejected(self) -> None:
        source = Image.open(build_icon_set.SOURCE_MARK_PATH).convert("RGBA")

        errors = validate_brand_assets.brand_mark_geometry_errors(source)

        self.assertTrue(
            any(
                "cat head must be horizontally centered" in error
                for error in errors
            )
        )

    def test_any_detached_trail_component_is_rejected(self) -> None:
        mark = Image.new("RGBA", (1024, 1024))
        draw = ImageDraw.Draw(mark)
        draw.rectangle(
            (312, 250, 712, 774),
            fill=(*build_icon_set.WHITE, 255),
        )
        draw.ellipse(
            (100, 600, 120, 620),
            fill=(*build_icon_set.TRAIL, 255),
        )

        errors = validate_brand_assets.brand_mark_geometry_errors(mark)

        self.assertIn("brand mark must not contain trail pixels", errors)

    def test_brand_layer_paths_are_required(self) -> None:
        self.assertIn("assets/images/brand_cat.png", validate_brand_assets.EXPECTED)
        self.assertIn("assets/images/brand_bolt.png", validate_brand_assets.EXPECTED)

    def test_brand_layer_with_opaque_corner_is_rejected(self) -> None:
        cat = self.cat.copy()
        cat.putpixel((0, 0), (*build_icon_set.WHITE, 255))

        errors = validate_brand_assets.brand_layer_errors(
            cat,
            self.refined,
            build_icon_set.WHITE,
            "brand_cat.png",
        )

        self.assertIn(
            "brand_cat.png must have transparent RGBA corners",
            errors,
        )

    def test_brand_layer_with_wrong_color_is_rejected(self) -> None:
        cat = Image.new("RGBA", self.cat.size, (*build_icon_set.YELLOW, 255))
        cat.putalpha(self.cat.getchannel("A"))

        errors = validate_brand_assets.brand_layer_errors(
            cat,
            self.refined,
            build_icon_set.WHITE,
            "brand_cat.png",
        )

        self.assertIn(
            "brand_cat.png color-class geometry must match the refined mark",
            errors,
        )


if __name__ == "__main__":
    unittest.main()

"""Pure geometry tests; these fixtures are not rendered runtime evidence."""
import copy
import unittest

from run_critical_path import image_geometry_matches


class DisplayMappingTests(unittest.TestCase):
    def setUp(self):
        # Native/virtual/raw/proxy dimensions from P02's reported 4.7.2 case.
        # Stretch is an explicit fixture; actual runs must observe their own transform.
        self.scaled = {
            "window_size": [3024, 1898], "root_size": [3024, 1898],
            "viewport_size": [1440, 904], "png_size": [3023, 1898],
            "texture_size": [6347, 3985], "content_scale_mode": 1,
            "content_scale_aspect": 1,
            "stretch_transform": [3023 / 1440, 0, 0, 1898 / 904, 0, 0],
        }

    def test_native_aspect_fit_image_does_not_equal_texture_proxy(self):
        self.assertTrue(image_geometry_matches(self.scaled, [3023, 1898]))

    def test_logical_or_proxy_sized_image_cannot_claim_native_capture(self):
        for size in ([1440, 904], [6347, 3985], [3024, 1898], [100, 100]):
            changed = copy.deepcopy(self.scaled)
            changed["png_size"] = size
            self.assertFalse(image_geometry_matches(changed, size))

    def test_arbitrary_transform_cannot_bypass_window_fit(self):
        changed = copy.deepcopy(self.scaled)
        changed.update(png_size=[1440, 904], stretch_transform=[1, 0, 0, 1, 0, 0])
        self.assertFalse(image_geometry_matches(changed, [1440, 904]))

    def test_unscaled_window_requires_exact_viewport_image(self):
        sample = dict(window_size=[844, 390], root_size=[844, 390], viewport_size=[844, 390],
                      png_size=[844, 390], texture_size=[844, 390], content_scale_mode=0,
                      content_scale_aspect=0, stretch_transform=[1, 0, 0, 1, 0, 0])
        self.assertTrue(image_geometry_matches(sample, [844, 390]))
        self.assertFalse(image_geometry_matches(sample, [843, 390]))


if __name__ == "__main__":
    unittest.main()

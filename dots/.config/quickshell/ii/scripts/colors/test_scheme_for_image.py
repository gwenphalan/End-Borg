import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from scheme_for_image import pick_scheme


class SchemeSelectionTests(unittest.TestCase):
    def test_grayscale(self):
        gradient = np.arange(256, dtype=np.uint8).reshape(16, 16)
        self.assertEqual(pick_scheme(np.stack([gradient] * 3, axis=-1)), "scheme-monochrome")

    def test_muted_color(self):
        self.assertEqual(pick_scheme(np.full((16, 16, 3), (125, 120, 115), dtype=np.uint8)),
                         "scheme-neutral")

    def test_dark_saturated_color_is_not_neutral(self):
        self.assertEqual(pick_scheme(np.full((16, 16, 3), (35, 9, 12), dtype=np.uint8)),
                         "scheme-tonal-spot")

    def test_moderate_single_hue(self):
        self.assertEqual(pick_scheme(np.full((16, 16, 3), (120, 170, 145), dtype=np.uint8)),
                         "scheme-content")

    def test_multiple_hues(self):
        image = np.empty((16, 16, 3), dtype=np.uint8)
        image[:8] = (160, 95, 95)
        image[8:] = (95, 160, 160)
        self.assertEqual(pick_scheme(image), "scheme-tonal-spot")

    def test_cli_and_missing_file(self):
        script = Path(__file__).with_name("scheme_for_image.py")
        with tempfile.TemporaryDirectory() as directory:
            picture = Path(directory) / "gray.png"
            Image.new("RGB", (16, 16), (80, 80, 80)).save(picture)
            result = subprocess.run([sys.executable, str(script), str(picture)],
                                    capture_output=True, text=True)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "scheme-monochrome"))
            missing = subprocess.run([sys.executable, str(script), str(picture) + ".missing"],
                                     capture_output=True, text=True)
            self.assertEqual((missing.returncode, missing.stdout.strip()), (1, "scheme-tonal-spot"))


if __name__ == "__main__":
    unittest.main()

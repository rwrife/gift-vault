import tempfile
import unittest
from pathlib import Path

try:
    import PIL.Image as PILImage

    HAS_PILLOW = True
except ImportError:  # pragma: no cover - Pillow is not preinstalled on every CI runner
    PILImage = None
    HAS_PILLOW = False


@unittest.skipUnless(HAS_PILLOW, "Pillow is not installed in this environment")

class GenerateAppIconTests(unittest.TestCase):
    def test_renders_opaque_1024_master_png(self):
        from Scripts.generate_app_icon import render_icon

        img = render_icon(1024)
        self.assertEqual(img.size, (1024, 1024))
        self.assertEqual(img.mode, "RGB")

    def test_file_output_is_valid_png(self):
        from Scripts.generate_app_icon import render_icon

        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "AppIcon.png"
        render_icon(256).save(path, format="PNG")
        reloaded = PILImage.open(path)
        self.assertEqual(reloaded.size, (256, 256))
        self.assertEqual(reloaded.mode, "RGB")


if __name__ == "__main__":
    unittest.main()

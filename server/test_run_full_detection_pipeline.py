import importlib
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


class RunFullDetectionPipelineLocaleTest(unittest.TestCase):
    def setUp(self):
        # Ensure the server directory is on sys.path so imports work in isolation
        server_dir = Path(__file__).resolve().parent
        if str(server_dir) not in sys.path:
            sys.path.insert(0, str(server_dir))
        sys.modules.pop("fashion_detector_server", None)

    def test_forwards_country_and_language(self):
        captured = {}

        with patch("transformers.AutoImageProcessor.from_pretrained", return_value=MagicMock(name="processor")), \
             patch("transformers.YolosForObjectDetection.from_pretrained", return_value=MagicMock(name="model")), \
             patch("cloudinary.config"), \
             patch("cloudinary.uploader.upload", return_value={"secure_url": "https://example.com/fake.jpg"}):

            fds = importlib.import_module("fashion_detector_server")

            def fake_search(image_url, max_results, location=None, country=None, language=None, merchant_hints=None):
                captured["country"] = country
                captured["language"] = language
                return []

            with patch.object(fds, "search_visual_products", side_effect=fake_search):
                result = fds.run_full_detection_pipeline(
                    image_url="https://example.com/test.jpg",
                    skip_detection=True,
                    country="NO",
                    language="nb",
                )

        self.assertTrue(result.get("success"))
        self.assertEqual(captured.get("country"), "NO")
        self.assertEqual(captured.get("language"), "nb")


if __name__ == "__main__":
    unittest.main()

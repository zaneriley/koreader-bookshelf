import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "reading_preset_qa.py"
SPEC = importlib.util.spec_from_file_location("reading_preset_qa", MODULE_PATH)
reading_preset_qa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reading_preset_qa)


DEFAULT_CAPTURE_ID = (
    "2026-05-08-latin-literary-prose-literary-latin-remarkable2-portrait"
)


def write_capture(root, capture_id=DEFAULT_CAPTURE_ID, **overrides):
    capture_dir = Path(root) / capture_id
    capture_dir.mkdir(parents=True)
    manifest = {
        "capture_id": capture_id,
        "fixture_id": "latin-literary-prose",
        "reading_preset_id": "literary-latin",
        "device_target": "remarkable2-portrait",
        "koreader_commit": "abc1234",
        "plugin_commit": "def5678",
        "page_anchor": "epubcfi(/6/2!/4/1:0)",
        "settings_snapshot": "settings.json",
        "full_page_screenshot": "full-page.png",
        "status_bar_footer_crop": "status-bar-footer.png",
        "visual_qa_note": "note.md",
    }
    manifest.update(overrides.pop("manifest", {}))
    note = {
        "reviewer": "Z",
        "date": "2026-05-08",
        "fixture_id": manifest["fixture_id"],
        "reading_preset_id": manifest["reading_preset_id"],
        "device_target": manifest["device_target"],
        "koreader_commit": manifest["koreader_commit"],
        "plugin_commit": manifest["plugin_commit"],
        "page_anchor": manifest["page_anchor"],
        "result": "pass",
        "rationale": "Footer zones remain separate.",
    }
    note.update(overrides.pop("note", {}))
    settings = overrides.pop("settings", {"footer": {"zone_gap": 32}})

    (capture_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )
    (capture_dir / "settings.json").write_text(
        json.dumps(settings, indent=2),
        encoding="utf-8",
    )
    (capture_dir / "full-page.png").write_bytes(b"png")
    (capture_dir / "status-bar-footer.png").write_bytes(b"png")
    (capture_dir / "note.md").write_text(
        "\n".join(f"{key}: {value}" for key, value in note.items()) + "\n",
        encoding="utf-8",
    )
    return capture_dir


class ReadingPresetQAToolTest(unittest.TestCase):
    def test_valid_capture_record_passes(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            write_capture(tmpdir)

            rows = reading_preset_qa.validate_capture_root(tmpdir, require_captures=True)

            self.assertEqual(1, len(rows))
            self.assertEqual("latin-literary-prose", rows[0]["fixture_id"])
            self.assertEqual("literary-latin", rows[0]["reading_preset_id"])
            self.assertEqual("pass", rows[0]["result"])

    def test_placeholder_manifest_fields_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            write_capture(tmpdir, manifest={"page_anchor": "[Z to fill]"})

            with self.assertRaises(reading_preset_qa.QAValidationError):
                reading_preset_qa.validate_capture_root(tmpdir, require_captures=True)

    def test_note_must_match_manifest_identity_fields(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            write_capture(tmpdir, note={"reading_preset_id": "koreader-default"})

            with self.assertRaises(reading_preset_qa.QAValidationError):
                reading_preset_qa.validate_capture_root(tmpdir, require_captures=True)

    def test_manifest_paths_must_stay_inside_capture_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            write_capture(tmpdir, manifest={"settings_snapshot": "../settings.json"})

            with self.assertRaises(reading_preset_qa.QAValidationError):
                reading_preset_qa.validate_capture_root(tmpdir, require_captures=True)

    def test_screenshots_must_be_png_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            write_capture(tmpdir, manifest={"full_page_screenshot": "full-page.jpg"})
            capture_dir = Path(tmpdir) / DEFAULT_CAPTURE_ID
            (capture_dir / "full-page.jpg").write_bytes(b"jpg")

            with self.assertRaises(reading_preset_qa.QAValidationError):
                reading_preset_qa.validate_capture_root(tmpdir, require_captures=True)

    def test_require_captures_rejects_empty_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with self.assertRaises(reading_preset_qa.QAValidationError):
                reading_preset_qa.validate_capture_root(tmpdir, require_captures=True)


if __name__ == "__main__":
    unittest.main()

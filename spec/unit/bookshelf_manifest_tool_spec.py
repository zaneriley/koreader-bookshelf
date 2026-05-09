import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "validate_bookshelf_manifest.py"
SPEC = importlib.util.spec_from_file_location("validate_bookshelf_manifest", MODULE_PATH)
validate_bookshelf_manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate_bookshelf_manifest)


class BookshelfManifestToolTest(unittest.TestCase):
    def test_rejects_legacy_measure_snapshot_field(self):
        with self.assertRaises(validate_bookshelf_manifest.ValidationError) as raised:
            validate_bookshelf_manifest.validate_manifest_values(
                {"capture_schema": {"measure_snapshot": "measure.json"}}
            )

        self.assertEqual(validate_bookshelf_manifest.EXIT_SCHEMA, raised.exception.exit_code)

    def test_rejects_host_local_paths(self):
        with self.assertRaises(validate_bookshelf_manifest.ValidationError) as raised:
            validate_bookshelf_manifest.validate_manifest_values(
                {"path": "/Users/example/private.png"}
            )

        self.assertEqual(validate_bookshelf_manifest.EXIT_REDACTION, raised.exception.exit_code)

    def test_rejects_windows_host_local_paths(self):
        with self.assertRaises(validate_bookshelf_manifest.ValidationError) as raised:
            validate_bookshelf_manifest.validate_manifest_values(
                {"path": r"C:\Users\Z\private.png"}
            )

        self.assertEqual(validate_bookshelf_manifest.EXIT_REDACTION, raised.exception.exit_code)

    def test_capture_json_rejects_legacy_measure_snapshot_field(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "capture").mkdir()
            (root / "capture" / "manifest.json").write_text(
                json.dumps({"measure_snapshot": "measure.json"}),
                encoding="utf-8",
            )

            with self.assertRaises(validate_bookshelf_manifest.ValidationError) as raised:
                validate_bookshelf_manifest.check_capture_json_contract(root)

        self.assertEqual(validate_bookshelf_manifest.EXIT_SCHEMA, raised.exception.exit_code)

    def test_plugin_directory_comparison_allows_exact_copy(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            source = root / "source"
            target = root / "target"
            source.mkdir()
            target.mkdir()
            (source / "main.lua").write_text("return {}\n", encoding="utf-8")
            (target / "main.lua").write_text("return {}\n", encoding="utf-8")

            validate_bookshelf_manifest.compare_plugin_source(source, target, "plugin")

    def test_plugin_directory_comparison_rejects_drift(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            source = root / "source"
            target = root / "target"
            source.mkdir()
            target.mkdir()
            (source / "main.lua").write_text("return {}\n", encoding="utf-8")
            (target / "main.lua").write_text("return { stale = true }\n", encoding="utf-8")

            with self.assertRaises(validate_bookshelf_manifest.ValidationError) as raised:
                validate_bookshelf_manifest.compare_plugin_source(source, target, "plugin")

        self.assertEqual(validate_bookshelf_manifest.EXIT_INTEGRITY, raised.exception.exit_code)


class BookshelfApplyToolTest(unittest.TestCase):
    def test_copy_directory_removes_stale_target_files(self):
        apply_path = Path(__file__).resolve().parents[2] / "tools" / "apply_to_koreader_checkout.py"
        spec = importlib.util.spec_from_file_location("apply_to_koreader_checkout", apply_path)
        apply_to_koreader_checkout = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(apply_to_koreader_checkout)

        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            source = root / "source"
            target = root / "target"
            source.mkdir()
            target.mkdir()
            (source / "main.lua").write_text("return {}\n", encoding="utf-8")
            (target / "stale.lua").write_text("return { stale = true }\n", encoding="utf-8")

            apply_to_koreader_checkout.copy_directory(source, target)

            self.assertTrue((target / "main.lua").exists())
            self.assertFalse((target / "stale.lua").exists())


if __name__ == "__main__":
    unittest.main()

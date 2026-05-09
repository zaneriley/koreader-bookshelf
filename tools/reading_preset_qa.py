#!/usr/bin/env python3
"""Validate promoted reading-preset visual QA capture records."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_MANIFEST_FIELDS = (
    "capture_id",
    "fixture_id",
    "reading_preset_id",
    "device_target",
    "koreader_commit",
    "plugin_commit",
    "page_anchor",
    "settings_snapshot",
    "font_pack_manifest",
    "full_page_screenshot",
    "text_block_crop",
    "status_bar_footer_crop",
    "readable_measure_snapshot",
    "visual_qa_note",
)

PATH_FIELDS = (
    "settings_snapshot",
    "font_pack_manifest",
    "full_page_screenshot",
    "text_block_crop",
    "status_bar_footer_crop",
    "readable_measure_snapshot",
    "visual_qa_note",
)

PNG_FIELDS = (
    "full_page_screenshot",
    "text_block_crop",
    "status_bar_footer_crop",
)

REQUIRED_NOTE_FIELDS = (
    "reviewer",
    "date",
    "fixture_id",
    "reading_preset_id",
    "device_target",
    "koreader_commit",
    "plugin_commit",
    "page_anchor",
    "result",
    "rationale",
)

MATCHING_NOTE_FIELDS = (
    "fixture_id",
    "reading_preset_id",
    "device_target",
    "koreader_commit",
    "plugin_commit",
    "page_anchor",
)

VALID_RESULTS = ("pass", "fail", "needs-followup")
VALID_GATE_RESULTS = ("pass", "fail", "needs-followup", "not-applicable")
VALID_FAILURE_OWNERS = (
    "Reading Preset tuning",
    "Readable Measure Rule",
    "Font Pack evidence",
    "Fixture rejection",
    "KOReader Profile Translator",
    "Publisher CSS Recovery Preset",
    "KOReader upstream issue",
    "CREngine renderer defect",
)
REQUIRED_MEASURE_FIELDS = (
    "median_cpl",
    "words_per_line",
    "gates",
)
REQUIRED_MEASURE_GATES = (
    "language_gate",
    "hyphenation_gate",
    "spacing_evenness_gate",
    "font_color_gate",
    "paragraph_rhythm_gate",
    "page_turn_gate",
)
REQUIRED_FONT_PACK_FIELDS = (
    "font_pack_id",
    "fonts",
)
PLACEHOLDER_VALUES = ("", "any", "todo", "tbd", "[z to fill]", "z to fill")
CAPTURE_ID_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-.+")


class QAValidationError(ValueError):
    """Raised when promoted reading-preset QA evidence is incomplete."""


def is_placeholder(value):
    if value is None:
        return True
    normalized = str(value).strip().lower()
    return normalized in PLACEHOLDER_VALUES or normalized.startswith("[z to fill")


def read_json_object(path):
    try:
        with Path(path).open(encoding="utf-8") as handle:
            value = json.load(handle)
    except OSError as err:
        raise QAValidationError(f"{path}: cannot read JSON: {err}") from err
    except json.JSONDecodeError as err:
        raise QAValidationError(f"{path}: invalid JSON: {err}") from err

    if not isinstance(value, dict):
        raise QAValidationError(f"{path}: expected a JSON object")
    return value


def parse_note(path):
    fields = {}
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError as err:
        raise QAValidationError(f"{path}: cannot read note: {err}") from err

    for line in lines:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key and key not in fields:
            fields[key] = value.strip()
    return fields


def path_within(parent, child):
    try:
        Path(child).resolve().relative_to(Path(parent).resolve())
        return True
    except ValueError:
        return False


def manifest_path(capture_dir):
    return Path(capture_dir) / "manifest.json"


def capture_dirs(root):
    root = Path(root)
    if not root.exists():
        return []
    return sorted(path for path in root.iterdir() if path.is_dir())


def expected_capture_id(manifest):
    date = manifest["capture_id"][:10]
    return (
        f"{date}-{manifest['fixture_id']}-"
        f"{manifest['reading_preset_id']}-{manifest['device_target']}"
    )


def resolve_capture_path(capture_dir, value, field):
    if Path(value).is_absolute():
        raise QAValidationError(
            f"{capture_dir}: {field} must be relative to the capture directory"
        )
    path = Path(capture_dir) / value
    if not path_within(capture_dir, path):
        raise QAValidationError(f"{capture_dir}: {field} points outside capture directory")
    if not path.exists():
        raise QAValidationError(f"{capture_dir}: {field} file does not exist: {value}")
    if not path.is_file():
        raise QAValidationError(f"{capture_dir}: {field} is not a file: {value}")
    if field in PNG_FIELDS and path.suffix.lower() != ".png":
        raise QAValidationError(f"{capture_dir}: {field} must be a PNG file: {value}")
    if field in PNG_FIELDS and path.stat().st_size == 0:
        raise QAValidationError(f"{capture_dir}: {field} must not be empty: {value}")
    return path


def parse_non_negative_number(path, payload, field):
    try:
        value = float(payload[field])
    except (TypeError, ValueError) as err:
        raise QAValidationError(f"{path}: {field} must be a number") from err
    if value < 0:
        raise QAValidationError(f"{path}: {field} must be non-negative")
    return value


def validate_font_pack(path):
    payload = read_json_object(path)
    missing = [field for field in REQUIRED_FONT_PACK_FIELDS if field not in payload]
    if missing:
        raise QAValidationError(
            f"{path}: Font Pack manifest is missing fields: {', '.join(missing)}"
        )
    placeholders = [
        field for field in REQUIRED_FONT_PACK_FIELDS if is_placeholder(payload.get(field))
    ]
    if placeholders:
        raise QAValidationError(
            f"{path}: Font Pack manifest has placeholder fields: {', '.join(placeholders)}"
        )
    if not isinstance(payload["fonts"], list) or not payload["fonts"]:
        raise QAValidationError(f"{path}: fonts must be a non-empty list")
    return payload


def validate_readable_measure_snapshot(path, note_result):
    payload = read_json_object(path)
    missing = [field for field in REQUIRED_MEASURE_FIELDS if field not in payload]
    if missing:
        raise QAValidationError(
            f"{path}: readable measure snapshot is missing fields: {', '.join(missing)}"
        )

    parse_non_negative_number(path, payload, "median_cpl")
    parse_non_negative_number(path, payload, "words_per_line")

    gates = payload["gates"]
    if not isinstance(gates, dict):
        raise QAValidationError(f"{path}: gates must be a JSON object")
    missing_gates = [field for field in REQUIRED_MEASURE_GATES if field not in gates]
    if missing_gates:
        raise QAValidationError(
            f"{path}: readable measure snapshot is missing gates: {', '.join(missing_gates)}"
        )
    invalid_gates = [
        field for field in REQUIRED_MEASURE_GATES
        if gates[field] not in VALID_GATE_RESULTS
    ]
    if invalid_gates:
        raise QAValidationError(
            f"{path}: gates must be one of {', '.join(VALID_GATE_RESULTS)}: "
            f"{', '.join(invalid_gates)}"
        )

    failure_owner = payload.get("failure_owner")
    if is_placeholder(failure_owner):
        failure_owner = None
    if note_result == "fail" and not failure_owner:
        raise QAValidationError(f"{path}: failed render cases require failure_owner")
    if failure_owner and failure_owner not in VALID_FAILURE_OWNERS:
        raise QAValidationError(
            f"{path}: failure_owner must be one of {', '.join(VALID_FAILURE_OWNERS)}"
        )

    return payload


def validate_manifest(capture_dir):
    capture_dir = Path(capture_dir)
    manifest = read_json_object(manifest_path(capture_dir))

    missing = [field for field in REQUIRED_MANIFEST_FIELDS if field not in manifest]
    if missing:
        raise QAValidationError(
            f"{capture_dir}: manifest is missing fields: {', '.join(missing)}"
        )

    placeholders = [
        field for field in REQUIRED_MANIFEST_FIELDS if is_placeholder(manifest.get(field))
    ]
    if placeholders:
        raise QAValidationError(
            f"{capture_dir}: manifest has placeholder fields: {', '.join(placeholders)}"
        )

    capture_id = str(manifest["capture_id"])
    if not CAPTURE_ID_RE.match(capture_id):
        raise QAValidationError(
            f"{capture_dir}: capture_id must start with YYYY-MM-DD-"
        )
    if capture_id != capture_dir.name:
        raise QAValidationError(
            f"{capture_dir}: capture_id {capture_id!r} does not match directory name"
        )
    expected = expected_capture_id(manifest)
    if capture_id != expected:
        raise QAValidationError(
            f"{capture_dir}: capture_id must be {expected!r} for this manifest"
        )

    resolved_paths = {
        field: resolve_capture_path(capture_dir, manifest[field], field)
        for field in PATH_FIELDS
    }

    settings = read_json_object(resolved_paths["settings_snapshot"])
    if not settings:
        raise QAValidationError(f"{capture_dir}: settings snapshot must not be empty")
    validate_font_pack(resolved_paths["font_pack_manifest"])

    note = parse_note(resolved_paths["visual_qa_note"])
    missing_note = [field for field in REQUIRED_NOTE_FIELDS if field not in note]
    if missing_note:
        raise QAValidationError(
            f"{capture_dir}: Visual QA Note is missing fields: {', '.join(missing_note)}"
        )

    placeholder_note = [
        field for field in REQUIRED_NOTE_FIELDS if is_placeholder(note.get(field))
    ]
    if placeholder_note:
        raise QAValidationError(
            f"{capture_dir}: Visual QA Note has placeholder fields: {', '.join(placeholder_note)}"
        )

    if note["result"] not in VALID_RESULTS:
        raise QAValidationError(
            f"{capture_dir}: result must be one of {', '.join(VALID_RESULTS)}"
        )

    mismatches = [
        field for field in MATCHING_NOTE_FIELDS if note[field] != str(manifest[field])
    ]
    if mismatches:
        raise QAValidationError(
            f"{capture_dir}: note does not match manifest fields: {', '.join(mismatches)}"
        )

    validate_readable_measure_snapshot(
        resolved_paths["readable_measure_snapshot"],
        note["result"],
    )

    return {
        "capture_id": capture_id,
        "fixture_id": manifest["fixture_id"],
        "reading_preset_id": manifest["reading_preset_id"],
        "device_target": manifest["device_target"],
        "result": note["result"],
    }


def validate_capture_root(root, require_captures=False):
    captures = capture_dirs(root)
    if require_captures and not captures:
        raise QAValidationError(f"{root}: no capture directories found")
    return [validate_manifest(path) for path in captures]


def build_parser():
    parser = argparse.ArgumentParser(
        description="Validate promoted reading-preset visual QA capture records."
    )
    subparsers = parser.add_subparsers(dest="action", required=True)

    validate_parser = subparsers.add_parser(
        "validate",
        help="validate all capture directories under a capture root",
    )
    validate_parser.add_argument("--captures", default="doc/captures")
    validate_parser.add_argument(
        "--require-captures",
        action="store_true",
        help="fail when the capture root has no capture directories",
    )
    return parser


def run_validate(args):
    rows = validate_capture_root(args.captures, args.require_captures)
    print(f"validated {len(rows)} reading-preset QA capture(s)")
    for row in rows:
        print(
            "{capture_id}: {fixture_id} x {reading_preset_id} x "
            "{device_target} => {result}".format(**row)
        )
    return 0


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.action == "validate":
            return run_validate(args)
        parser.error(f"unknown command {args.action}")
    except QAValidationError as err:
        print(f"reading_preset_qa.py: error: {err}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

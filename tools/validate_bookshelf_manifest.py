#!/usr/bin/env python3
"""Validate the KOReader Bookshelf manifest and local integration boundary."""

from __future__ import annotations

import argparse
import filecmp
import json
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


EXIT_SCHEMA = 1
EXIT_PATH = 2
EXIT_INTEGRITY = 3
EXIT_REDACTION = 4

PROJECT = "koreader-bookshelf"
MANIFEST_PATH = Path("manifests/bookshelf.json")
LEGACY_FIELD_NAMES = {"measure_snapshot", "measure_snapshot_record"}
PLACEHOLDERS = {"", "any", "todo", "tbd", "[z to fill]", "z to fill"}
KNOWN_KINDS = {
    "plugin_source",
    "koreader_checkout",
    "plugin_integration_path",
    "device_target",
    "capture_schema",
}
HOST_PATH_PATTERNS = (
    re.compile(r"(^|[\s:=,\[\{'\"])/(Users|home)/"),
    re.compile(r"(^|[\s:=,\[\{'\"])[A-Za-z]:\\"),
    re.compile(r"(^|[\s:=,\[\{'\"])\\\\[^\\/\s]+\\[^\\/\s]+"),
)


class ValidationError(ValueError):
    """Raised for a deterministic manifest validation failure."""

    def __init__(self, exit_code: int, message: str):
        super().__init__(message)
        self.exit_code = exit_code


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def is_placeholder(value: object) -> bool:
    normalized = str(value).strip().lower()
    return normalized in PLACEHOLDERS or normalized.startswith("[z to fill")


def load_json_object(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as err:
        raise ValidationError(EXIT_PATH, f"{path}: cannot read manifest: {err}") from err
    except json.JSONDecodeError as err:
        raise ValidationError(EXIT_SCHEMA, f"{path}: invalid JSON: {err}") from err
    if not isinstance(payload, dict):
        raise ValidationError(EXIT_SCHEMA, f"{path}: manifest must be a JSON object")
    return payload


def contains_host_path(value: str) -> bool:
    return value.startswith("/Users/") or any(
        pattern.search(value) for pattern in HOST_PATH_PATTERNS
    )


def trail_name(trail: tuple[object, ...]) -> str:
    return ".".join(str(part) for part in trail)


def validate_manifest_values(value: object, trail: tuple[object, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in LEGACY_FIELD_NAMES:
                raise ValidationError(
                    EXIT_SCHEMA,
                    f"{trail_name(trail + (key,))}: legacy field name is banned; "
                    "use readable_measure_snapshot",
                )
            validate_manifest_values(child, trail + (key,))
        return
    if isinstance(value, list):
        for index, child in enumerate(value):
            validate_manifest_values(child, trail + (index,))
        return
    if isinstance(value, str):
        if is_placeholder(value):
            raise ValidationError(
                EXIT_SCHEMA,
                f"{trail_name(trail)}: placeholder values are not allowed",
            )
        if contains_host_path(value):
            raise ValidationError(
                EXIT_REDACTION,
                f"{trail_name(trail)}: manifest must not contain host-local paths",
            )


def reject_parent_ref(path: str, field: str) -> None:
    pure = PurePosixPath(path)
    if pure.is_absolute():
        raise ValidationError(EXIT_PATH, f"{field}: path must be relative: {path}")
    if ".." in pure.parts:
        raise ValidationError(EXIT_PATH, f"{field}: path must not contain '..': {path}")


def resolve_project_path(root: Path, path: str, field: str) -> Path:
    reject_parent_ref(path, field)
    return root / Path(path)


def require_path_exists(path: Path, field: str) -> None:
    if not path.exists():
        raise ValidationError(EXIT_PATH, f"{field}: path does not exist: {path}")


def artifacts_by_id(manifest: dict) -> dict[str, dict]:
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ValidationError(EXIT_SCHEMA, "artifacts must be a non-empty list")

    by_id: dict[str, dict] = {}
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict):
            raise ValidationError(EXIT_SCHEMA, f"artifacts.{index}: must be an object")
        artifact_id = artifact.get("id")
        kind = artifact.get("kind")
        if not isinstance(artifact_id, str):
            raise ValidationError(EXIT_SCHEMA, f"artifacts.{index}.id: must be a string")
        if artifact_id in by_id:
            raise ValidationError(EXIT_SCHEMA, f"artifacts.{index}.id: duplicate id {artifact_id}")
        if kind not in KNOWN_KINDS:
            raise ValidationError(
                EXIT_SCHEMA,
                f"{artifact_id}.kind: expected one of {', '.join(sorted(KNOWN_KINDS))}",
            )
        by_id[artifact_id] = artifact
    return by_id


def resolve_checkout(root: Path, artifact: dict, checkout_override: str | None) -> Path:
    if checkout_override:
        return Path(checkout_override).expanduser().resolve()

    env_name = artifact.get("path_environment_variable")
    if isinstance(env_name, str) and os.environ.get(env_name):
        return Path(os.environ[env_name]).expanduser().resolve()

    sibling = artifact.get("default_sibling_directory")
    if not isinstance(sibling, str):
        raise ValidationError(
            EXIT_SCHEMA,
            f"{artifact['id']}: must define default_sibling_directory or use --checkout",
        )
    if "/" in sibling or "\\" in sibling or sibling in {".", ".."}:
        raise ValidationError(
            EXIT_PATH,
            f"{artifact['id']}.default_sibling_directory: must be a sibling directory name",
        )
    return (root.parent / sibling).resolve()


def validate_static_artifacts(root: Path, by_id: dict[str, dict], checkout_override: str | None) -> dict[str, Path]:
    resolved: dict[str, Path] = {}

    for artifact in by_id.values():
        kind = artifact["kind"]
        artifact_id = artifact["id"]
        if kind == "plugin_source":
            path = resolve_project_path(root, artifact.get("path", ""), f"{artifact_id}.path")
            require_path_exists(path, f"{artifact_id}.path")
            if not path.is_dir():
                raise ValidationError(EXIT_PATH, f"{artifact_id}.path: must be a directory")
            resolved[artifact_id] = path
        elif kind == "koreader_checkout":
            checkout = resolve_checkout(root, artifact, checkout_override)
            require_path_exists(checkout, artifact_id)
            for rel_path in artifact.get("required_paths", []):
                reject_parent_ref(rel_path, f"{artifact_id}.required_paths")
                require_path_exists(checkout / rel_path, f"{artifact_id}.required_paths")
            resolved[artifact_id] = checkout
        elif kind == "plugin_integration_path":
            checkout_id = artifact.get("checkout_artifact")
            source_id = artifact.get("source_artifact")
            if checkout_id not in by_id:
                raise ValidationError(EXIT_SCHEMA, f"{artifact_id}.checkout_artifact: unknown id")
            if source_id not in by_id:
                raise ValidationError(EXIT_SCHEMA, f"{artifact_id}.source_artifact: unknown id")
            path = artifact.get("path")
            if not isinstance(path, str):
                raise ValidationError(EXIT_SCHEMA, f"{artifact_id}.path: must be a string")
            reject_parent_ref(path, f"{artifact_id}.path")
        elif kind == "device_target":
            for field in ("width", "height", "dpi"):
                value = artifact.get(field)
                if not isinstance(value, int) or value <= 0:
                    raise ValidationError(EXIT_SCHEMA, f"{artifact_id}.{field}: must be a positive integer")
        elif kind == "capture_schema":
            root_path = resolve_project_path(root, artifact.get("root", ""), f"{artifact_id}.root")
            require_path_exists(root_path, f"{artifact_id}.root")
            required = artifact.get("required_manifest_fields")
            if not isinstance(required, list) or "readable_measure_snapshot" not in required:
                raise ValidationError(
                    EXIT_SCHEMA,
                    f"{artifact_id}.required_manifest_fields: must include readable_measure_snapshot",
                )
            resolved[artifact_id] = root_path

    return resolved


def collect_files(root: Path) -> dict[str, Path]:
    return {
        str(path.relative_to(root)): path
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def compare_plugin_source(source: Path, target: Path, artifact_id: str) -> None:
    if target.is_symlink():
        if target.resolve() != source.resolve():
            raise ValidationError(
                EXIT_INTEGRITY,
                f"{artifact_id}: symlink points to {target.resolve()}, expected {source.resolve()}",
            )
        return

    if not target.exists():
        raise ValidationError(EXIT_PATH, f"{artifact_id}: integration path is missing: {target}")
    if not target.is_dir():
        raise ValidationError(EXIT_PATH, f"{artifact_id}: integration path must be a directory")

    source_files = collect_files(source)
    target_files = collect_files(target)
    missing = sorted(set(source_files) - set(target_files))
    extra = sorted(set(target_files) - set(source_files))
    changed = sorted(
        rel_path
        for rel_path in set(source_files) & set(target_files)
        if not filecmp.cmp(source_files[rel_path], target_files[rel_path], shallow=False)
    )
    if missing or extra or changed:
        details = []
        if missing:
            details.append(f"missing={missing[:5]}")
        if extra:
            details.append(f"extra={extra[:5]}")
        if changed:
            details.append(f"changed={changed[:5]}")
        raise ValidationError(
            EXIT_INTEGRITY,
            f"{artifact_id}: plugin mirror differs from source ({'; '.join(details)})",
        )


def integration_targets(by_id: dict[str, dict], resolved: dict[str, Path]) -> list[tuple[dict, Path, Path]]:
    targets = []
    for artifact in by_id.values():
        if artifact["kind"] != "plugin_integration_path":
            continue
        checkout = resolved[artifact["checkout_artifact"]]
        source = resolved[artifact["source_artifact"]]
        target = checkout / artifact["path"]
        targets.append((artifact, source, target))
    return targets


def parse_git_status_line(line: str) -> str:
    path = line[3:]
    if " -> " in path:
        path = path.split(" -> ", 1)[1]
    return path


def check_clean_layer(checkout: Path, allowed_prefixes: list[str], mode: str) -> None:
    try:
        result = subprocess.run(
            ["git", "-C", str(checkout), "status", "--porcelain=v1", "--untracked-files=all"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as err:
        raise ValidationError(EXIT_INTEGRITY, f"{checkout}: cannot read git status: {err}") from err

    if mode == "core-infrastructure":
        return

    violations = []
    normalized_prefixes = [prefix.rstrip("/") + "/" for prefix in allowed_prefixes]
    for line in result.stdout.splitlines():
        if not line:
            continue
        path = parse_git_status_line(line)
        allowed = any(path == prefix.rstrip("/") or path.startswith(prefix) for prefix in normalized_prefixes)
        if not allowed:
            violations.append(f"{line[:2]} {path}")

    if violations:
        raise ValidationError(
            EXIT_INTEGRITY,
            "KOReader checkout has changes outside manifest plugin integration paths: "
            + "; ".join(violations[:10]),
        )


def check_legacy_json_fields(value: object, source: Path, trail: tuple[object, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in LEGACY_FIELD_NAMES:
                raise ValidationError(
                    EXIT_SCHEMA,
                    f"{source}:{trail_name(trail + (key,))}: legacy field name is banned; "
                    "use readable_measure_snapshot",
                )
            check_legacy_json_fields(child, source, trail + (key,))
        return
    if isinstance(value, list):
        for index, child in enumerate(value):
            check_legacy_json_fields(child, source, trail + (index,))


def check_capture_json_contract(capture_root: Path) -> None:
    if not capture_root.exists():
        return
    for path in sorted(capture_root.rglob("*.json")):
        text = path.read_text(encoding="utf-8")
        if contains_host_path(text):
            raise ValidationError(EXIT_REDACTION, f"{path}: contains a host-local path")
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as err:
            raise ValidationError(EXIT_SCHEMA, f"{path}: invalid JSON: {err}") from err
        check_legacy_json_fields(payload, path)


def validate(args: argparse.Namespace) -> None:
    root = project_root()
    manifest_path = root / args.manifest
    manifest = load_json_object(manifest_path)
    validate_manifest_values(manifest)

    if manifest.get("schema_version") != 1:
        raise ValidationError(EXIT_SCHEMA, "schema_version must be 1")
    if manifest.get("project") != PROJECT:
        raise ValidationError(EXIT_SCHEMA, f"project must be {PROJECT}")

    by_id = artifacts_by_id(manifest)
    resolved = validate_static_artifacts(root, by_id, args.checkout)

    allowed_prefixes = []
    checkout_paths = []
    for artifact, source, target in integration_targets(by_id, resolved):
        compare_plugin_source(source, target, artifact["id"])
        allowed_prefixes.append(artifact["path"])
        checkout_paths.append(resolved[artifact["checkout_artifact"]])

    if args.strict:
        for checkout in sorted(set(checkout_paths)):
            check_clean_layer(checkout, allowed_prefixes, args.mode)

    for artifact in by_id.values():
        if artifact["kind"] == "capture_schema":
            check_capture_json_contract(resolved[artifact["id"]])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate the KOReader Bookshelf manifest and integration mirror."
    )
    parser.add_argument("--manifest", default=str(MANIFEST_PATH))
    parser.add_argument("--checkout", help="KOReader checkout path; overrides KOREADER_CHECKOUT")
    parser.add_argument("--strict", action="store_true", help="also enforce checkout clean-layer status")
    parser.add_argument(
        "--mode",
        choices=("plugin", "core-infrastructure"),
        default="plugin",
        help="validation mode for KOReader checkout changes",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        validate(args)
    except ValidationError as err:
        print(f"bookshelf manifest validation failed: {err}", file=sys.stderr)
        return err.exit_code
    print("bookshelf manifest validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

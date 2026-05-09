#!/usr/bin/env python3
"""Apply the canonical Bookshelf plugin source to a KOReader checkout."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path


MANIFEST_PATH = Path("manifests/bookshelf.json")


class ApplyError(ValueError):
    """Raised when the KOReader checkout cannot be updated safely."""


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_manifest(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as err:
        raise ApplyError(f"{path}: cannot read manifest: {err}") from err
    except json.JSONDecodeError as err:
        raise ApplyError(f"{path}: invalid JSON: {err}") from err


def by_id(manifest: dict) -> dict[str, dict]:
    return {artifact["id"]: artifact for artifact in manifest.get("artifacts", [])}


def resolve_checkout(root: Path, artifact: dict, override: str | None) -> Path:
    if override:
        return Path(override).expanduser().resolve()
    env_name = artifact.get("path_environment_variable")
    if isinstance(env_name, str) and os.environ.get(env_name):
        return Path(os.environ[env_name]).expanduser().resolve()
    sibling = artifact.get("default_sibling_directory")
    if not isinstance(sibling, str):
        raise ApplyError("KOReader checkout requires --checkout or a manifest default sibling")
    return (root.parent / sibling).resolve()


def path_within(parent: Path, child: Path) -> bool:
    try:
        child.resolve(strict=False).relative_to(parent.resolve(strict=False))
        return True
    except ValueError:
        return False


def ensure_safe_integration_target(checkout: Path, target: Path) -> None:
    if not path_within(checkout, target):
        raise ApplyError(f"{target}: integration target must stay inside {checkout}")
    if target.parent.name != "plugins" or not target.name.endswith(".koplugin"):
        raise ApplyError(f"{target}: expected a KOReader plugins/*.koplugin target")


def copy_directory(source: Path, target: Path) -> None:
    if target.is_symlink():
        if target.resolve() == source.resolve():
            return
        raise ApplyError(f"{target}: refuses to overwrite symlink to {target.resolve()}")
    if target.exists() and not target.is_dir():
        raise ApplyError(f"{target}: refuses to overwrite non-directory path")
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target)


def apply_manifest(manifest_path: Path, checkout_override: str | None) -> list[str]:
    root = project_root()
    manifest = load_manifest(manifest_path)
    artifacts = by_id(manifest)
    messages = []

    for artifact in artifacts.values():
        if artifact.get("kind") != "plugin_integration_path":
            continue
        checkout_artifact = artifacts[artifact["checkout_artifact"]]
        source_artifact = artifacts[artifact["source_artifact"]]
        checkout = resolve_checkout(root, checkout_artifact, checkout_override)
        if not (checkout / "reader.lua").exists():
            raise ApplyError(f"{checkout}: does not look like a KOReader checkout")
        source = root / source_artifact["path"]
        target = checkout / artifact["path"]
        ensure_safe_integration_target(checkout, target)
        copy_directory(source, target)
        messages.append(f"{source} -> {target}")

    if not messages:
        raise ApplyError("manifest has no plugin_integration_path artifacts")
    return messages


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Apply the canonical Bookshelf plugin to a KOReader checkout."
    )
    parser.add_argument("--manifest", default=str(MANIFEST_PATH))
    parser.add_argument("--checkout", help="KOReader checkout path; overrides KOREADER_CHECKOUT")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        messages = apply_manifest(project_root() / args.manifest, args.checkout)
    except ApplyError as err:
        print(f"bookshelf apply failed: {err}", file=sys.stderr)
        return 1
    for message in messages:
        print(f"applied {message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

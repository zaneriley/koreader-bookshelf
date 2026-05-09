# Architecture Decisions

## ADR-0001 - Bookshelf Manifest Defines Local Integration Boundaries

Status: draft, pending Z ratification

Context:

Bookshelf is a high-craft KOReader UX prototype, but local development has two physical surfaces that can drift: this repository's plugin source and a KOReader checkout's plugin mirror. That drift made browser previews untrustworthy because a container could mount `koreader/plugins/bookshelf.koplugin/` while the real work lived in `koreader-bookshelf/bookshelf.koplugin/`.

Decision:

`manifests/bookshelf.json` is the repo-owned contract for local integration boundaries. It names the canonical plugin source, the KOReader checkout discovery mechanism, the generated plugin integration path, the target device geometry, and the capture schema. Tooling must consume this manifest instead of hard-coding those facts in hooks, previews, or ad hoc commands.

Consequences:

- `bookshelf.koplugin/` is the editing surface.
- `plugins/bookshelf.koplugin/` inside a KOReader checkout is a generated mirror.
- `tools/apply_to_koreader_checkout.py` updates the generated mirror.
- `tools/validate_bookshelf_manifest.py --strict` proves the mirror, manifest, and checkout boundary are coherent.
- KOReader upstream work remains separate from plugin taste: generic infrastructure may be proposed upstream, while Bookshelf-specific UX stays in the plugin.

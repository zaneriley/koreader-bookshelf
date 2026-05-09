# AGENTS.md - KOReader Bookshelf

## Source Boundary

- Canonical plugin source lives in `bookshelf.koplugin/`.
- A KOReader checkout's `plugins/bookshelf.koplugin/` is a generated integration mirror, not an editing surface.
- The project contract lives in `manifests/bookshelf.json`; automation and hooks should read that manifest instead of duplicating project semantics.
- Durable architectural decisions belong in `ADRS.md`. Scratch plans and raw review output stay in `.tmp/`.

## Required Loop

Before trusting a local preview:

```sh
export KOREADER_CHECKOUT=/path/to/koreader
python3 tools/apply_to_koreader_checkout.py
python3 tools/validate_bookshelf_manifest.py --strict
```

The validator must exit `0` before calling a development environment ready. A nonzero result means the agent must fix the source boundary, manifest schema, redaction issue, or checkout drift before continuing UX work.

## Upstream Boundary

- Bookshelf-specific UX belongs in this plugin repo.
- KOReader core changes must be generic infrastructure, not Bookshelf taste. Examples: startup hooks, navigation-return behavior, footer slot layout, or profile application APIs.
- Public PR evidence must use generic tests, generic fixtures, or redacted reproduction bundles. Private screenshots, private library metadata, local paths, and copyrighted page captures stay in `.tmp/` or the private vault.

## Reading Preset Evidence

Promoted reading-preset captures live under `doc/captures/` and must pass:

```sh
python3 tools/reading_preset_qa.py validate --captures doc/captures --require-captures
```

Capture manifests use `readable_measure_snapshot`. The legacy names `measure_snapshot` and `measure_snapshot_record` are not valid schema.

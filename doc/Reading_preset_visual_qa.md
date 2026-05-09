# Reading Preset Visual QA

This document defines how we test reading-screen typography and status
bar/footer changes across diverse EPUBs. It exists to make visual review
repeatable: same fixture, same page anchor, same reading preset, same device
target, same evidence.

The goal is not to replace KOReader's renderer tests. The goal is to review our
private reading taste against real pages without smuggling that taste into
KOReader core.

## Boundary

KOReader core owns generic rendering behavior, status bar/footer behavior, and
upstreamable settings surfaces. Core changes must stand on their own without
depending on this plugin's screenshots or reMarkable-specific taste.

Bookshelf owns the private reading experience layer: reading presets, the
Reading Preset to KOReader Profile export/apply path, and designer-facing
visual QA evidence.

The plugin repo owns durable fixture definitions, capture schemas, promoted
screenshots, and synthesized design notes. Iteration scratch and unresolved
designer comments belong in `.tmp/` or the private Obsidian Backlog until they
are distilled into this doc or another durable plugin document.

## Glossary

| Term | Meaning |
| --- | --- |
| KOReader Profile | KOReader's existing Profiles plugin artifact. Use this term only for the upstream/native profile mechanism. |
| Reading Preset | A Bookshelf-owned manifest with intent, exact KOReader settings or KOReader Profile export, evidence render cases, and rationale for every setting delta. It translates private Bookshelf vocabulary into existing KOReader terms such as Profiles, Typography rules, Style tweaks, Embedded CSS, and Status Bar/Footer settings. |
| Readable Measure Rule | A Bookshelf-owned rule that turns a target measure range, viewport, typeface, and body size into a readable text-block target for a Latin-script preset. |
| KOReader Profile Translator | The Bookshelf adapter that turns a Readable Measure Rule result into existing KOReader profile actions and settings. |
| Private Default Reading Preset | A Bookshelf UX candidate only. It is never an upstream KOReader default and is applied only through explicit user or plugin action. |
| Publisher CSS Recovery Preset | A non-default runtime Reading Preset used for source-quality stress cases where publisher CSS damages readability. It changes only KOReader settings, preserves the source EPUB, records all overrides, and never becomes any default. |
| Font Pack | A manifest-backed set of font files with roles, licenses, hashes, family names, fallbacks, and observed KOReader behavior. |
| Fixture | A specific EPUB test input with source identity, file hash, stable page anchor, fixture facets, and expected rendering risks. |
| Fixture Candidate | An incomplete fixture row. It cannot satisfy any QA gate until all required fixture fields are filled. |
| Fixture Facets | The attributes that explain why a fixture exists: language, script, direction, writing mode, content features, and source quality. |
| Reading Preset ID | The applied preset in a render case, such as `koreader-default`, `literary-latin`, or `publisher-css-recovery`. |
| Device Target | A named screen geometry and density, such as `remarkable2-portrait`. |
| Render Case | One cell in the QA matrix: fixture x reading preset ID x device target. |
| KOReader Settings Snapshot | The captured KOReader settings used to produce a render case. |
| Visual QA Note | A structured note file tied to one render case, with reviewer, date, evidence, and pass/fail rationale. |
| Status Bar/Footer | KOReader's reader chrome at the bottom of the page. Use this phrase when discussing the upstream concept. |
| Footer Zone | Local QA term for one of the three rendered status bar/footer groups: start, center, or end. |

## Matrix Model

The visual matrix is:

```text
Render Case = Fixture x Reading Preset ID x Device Target
```

Do not collapse preset and device into one axis. If a render looks wrong, we
need to know whether the failure came from content, settings, or screen
geometry.

## Fixture Facets

Every fixture records these facets:

| Facet | Examples |
| --- | --- |
| Language | English, Japanese, Chinese, Korean, mixed |
| Script | Latin, Han, Kana, Hangul, mixed Latin/CJK |
| Direction | LTR, RTL, top-to-bottom |
| Writing mode | horizontal, vertical |
| Content features | chaptered prose, footnotes, headings, lists, ruby, poetry, images |
| Source quality | clean publisher CSS, publisher CSS stress, broken line height, nonsemantic markup |

## Fixture Candidates

The starter set should be small enough to review in one session but varied
enough to catch false confidence. Rows in this table are candidates until the
source identity, file hash, page anchor, and risk notes are filled. Fixture
candidates cannot satisfy any render-case or promotion gate.

| Fixture ID | Language | Script | Direction | Writing mode | Content features | Source quality | Source identity | File hash | Page anchor | Risk notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `latin-literary-prose` | [Z to fill] | Latin | LTR | horizontal | chaptered prose | clean publisher CSS | [Z to fill] | [Z to fill] | [Z to fill] | [Z to fill] |
| `japanese-horizontal-prose` | Japanese | Han/Kana | LTR or RTL by publication | horizontal | chaptered prose | clean publisher CSS | [Z to fill] | [Z to fill] | [Z to fill] | CJK line breaking, footer labels |
| `japanese-vertical-prose` | Japanese | Han/Kana | top-to-bottom | vertical | chaptered prose, punctuation/ruby if available | clean publisher CSS | [Z to fill] | [Z to fill] | [Z to fill] | vertical body with horizontal chrome |
| `notes-footnote-nonfiction` | [Z to fill] | Latin or mixed | LTR | horizontal | headings, lists, footnotes | clean publisher CSS | [Z to fill] | [Z to fill] | [Z to fill] | notes and hierarchy |
| `publisher-css-stress` | [Z to fill] | [Z to fill] | [Z to fill] | [Z to fill] | [Z to fill] | publisher CSS stress | [Z to fill] | [Z to fill] | [Z to fill] | publisher styling damages readability |
| `broken-line-height` | [Z to fill] | [Z to fill] | [Z to fill] | [Z to fill] | prose | broken line height | [Z to fill] | [Z to fill] | [Z to fill] | line rhythm stress |

`publisher-css-stress` and `broken-line-height` are not value judgments about a
book. They are source-quality stress cases. Use the fixture IDs in durable docs.

## Fixture Promotion Gate

A fixture becomes active only when all of these fields are complete:

1. Source identity: title, author when available, and local EPUB path or fixture
   corpus reference.
2. File hash: a stable checksum for the exact EPUB used in captures.
3. Page anchor: the KOReader location used to reopen the same page.
4. Facets: language, script, direction, writing mode, content features, and
   source quality.
5. Risk notes: the rendering behavior this fixture is meant to expose.

No placeholder row, `Any` value, or `[Z to fill]` value counts as coverage.

## Reading Presets

| Reading Preset ID | Purpose | Default eligibility |
| --- | --- | --- |
| `koreader-default` | Baseline render with stock KOReader settings. | `upstream-baseline-only` |
| `literary-latin` | Private large-screen e-ink preset for Latin prose. | `private-default-candidate` |
| `cjk-horizontal` | Private preset for horizontal CJK prose. | `private-default-candidate` |
| `cjk-vertical-publisher` | Publisher-preserving preset for vertical CJK books. | `private-default-candidate` |
| `publisher-css-recovery` | Explicit runtime recovery preset for source-quality stress fixtures. | `explicit-only-never-default` |

The `publisher-css-recovery` preset must never become the upstream KOReader
default or the private default Reading Preset. It exists for explicit recovery
from damaged publisher styling, applies KOReader settings only, preserves the
source EPUB, and records all overrides in the KOReader Settings Snapshot.

## Device Targets

| Device Target | Size | DPI | Purpose |
| --- | --- | ---: | --- |
| `remarkable2-portrait` | 1404 x 1872 | 226 | Primary large e-ink target |
| `remarkable2-landscape` | 1872 x 1404 | 226 | Width-change and footer-spacing check |

Future device-target candidates stay outside the active target table until size
and DPI are known. `narrow-eink-portrait` is an open candidate, not an active
target.

## Capture Schema

Each render case captures:

| Field | Description |
| --- | --- |
| `capture_id` | Stable ID: `<date>-<fixture_id>-<reading_preset_id>-<device_target>`. |
| `fixture_id` | Fixture table ID. |
| `reading_preset_id` | Reading Preset table ID. |
| `device_target` | Device target table ID. |
| `koreader_commit` | KOReader commit used for the capture. |
| `plugin_commit` | Bookshelf plugin commit used for the capture. |
| `page_anchor` | Location used to reopen the same page. |
| `settings_snapshot` | Path to the KOReader Settings Snapshot. |
| `font_pack_manifest` | Path to the Font Pack manifest used by the render case. |
| `full_page_screenshot` | Path to the full reading page screenshot. |
| `text_block_crop` | Path to the body text-block crop used for measure and texture review. |
| `status_bar_footer_crop` | Path to the bottom status bar/footer crop. |
| `readable_measure_snapshot` | Path to the readable-measure JSON snapshot, including measured line metrics and gate results. |
| `visual_qa_note` | Path to the Visual QA Note file. |

Raw capture runs may start in `.tmp/<date>-reading-preset-qa/`. Promote only
complete render-case records into `doc/captures/<capture_id>/`. Use
`doc/images/` only for promoted excerpts referenced by README or design docs.

Each promoted capture directory contains:

```text
doc/captures/<capture_id>/
  manifest.json
  settings.json
  font-pack.json
  measure.json
  full-page.png
  text-block.png
  status-bar-footer.png
  note.md
```

Manifest paths are relative to the promoted capture directory. The validator
rejects absolute paths and `..` paths so private scratch evidence cannot leak
into a durable capture record by accident.

## Evidence Per Render Case

Each render case needs seven pieces of evidence:

1. Full page screenshot.
2. Text-block crop.
3. Status bar/footer crop.
4. KOReader Settings Snapshot.
5. Font Pack manifest.
6. Readable-measure snapshot.
7. Visual QA Note with reviewer, date, pass/fail, and rationale.

The readable-measure snapshot is JSON:

```json
{
  "median_cpl": 64,
  "words_per_line": 12,
  "gates": {
    "language_gate": "pass",
    "hyphenation_gate": "pass",
    "spacing_evenness_gate": "pass",
    "font_color_gate": "pass",
    "paragraph_rhythm_gate": "pass",
    "page_turn_gate": "not-applicable"
  },
  "failure_owner": ""
}
```

Gate values are `pass`, `fail`, `needs-followup`, or `not-applicable`.
Failed render cases must name one failure owner:

- `Reading Preset tuning`
- `Readable Measure Rule`
- `Font Pack evidence`
- `Fixture rejection`
- `KOReader Profile Translator`
- `Publisher CSS Recovery Preset`
- `KOReader upstream issue`
- `CREngine renderer defect`

The Visual QA Note must include enough provenance to reproduce the render:

```text
reviewer:
date:
fixture_id:
reading_preset_id:
device_target:
koreader_commit:
plugin_commit:
page_anchor:
result: pass | fail | needs-followup
rationale:
```

## Acceptance Criteria

### Core Invariants

These are the upstream-safe checks. They should be testable without accepting
our private reading taste.

| Check | Evidence |
| --- | --- |
| Footer Zones never overlap. | Status Bar/Footer crop plus mandatory pixel or layout geometry check. |
| Configured Footer Zone gap is honored. | Status Bar/Footer crop plus mandatory layout calculation. |
| CJK footer labels stay CJK and clamp without UTF-8 corruption. | CJK render cases and status bar/footer crop. |
| Body text does not collide with the status bar/footer. | Full page screenshot and bottom crop. |
| Vertical CJK body text can keep horizontal status bar/footer chrome. | `japanese-vertical-prose` render cases. |

Geometry checks are not optional for promoted render cases. If the current
capture tooling cannot produce the required pixel or layout evidence, mark the
render case `manual-review-only`; it cannot satisfy a core invariant gate.

### Reading Preset Expectations

These are private Bookshelf expectations. They inform our preset choices but do
not belong in a KOReader core PR as default behavior.

| Preset | Expectation |
| --- | --- |
| `literary-latin` | Comfortable line measure, stable paragraph rhythm, usable hyphenation, and no crowding near the footer. |
| `cjk-horizontal` | CJK line behavior is not forced through Latin word-spacing assumptions. |
| `cjk-vertical-publisher` | Publisher-declared vertical writing is preserved; footer chrome remains readable. |
| `publisher-css-recovery` | Damaged publisher CSS is made readable with runtime KOReader settings only, without mutating the EPUB or becoming any default preset. |

The Bookshelf private status bar/footer expectation is currently a 32 scaled px
minimum gap between Footer Zones. That number is private preset evidence, not a
generic KOReader core invariant.

Every Reading Preset change must cite a failed review question, list the exact
KOReader setting delta, and include before/after render-case evidence.
Non-recovery presets preserve publisher CSS unless a named invariant fails.

### Human Review Rubric

The designer review answers these questions per render case:

| Question | Response |
| --- | --- |
| Does the page feel readable for a full session? | pass/fail plus rationale |
| Does the preset respect publisher intent for this fixture? | pass/fail plus rationale |
| Is the footer useful without feeling like a dashboard? | pass/fail plus rationale |
| Does any label, line, or glyph feel cramped or visually unstable? | pass/fail plus rationale |
| Should this result change the preset, fixture, or create a core candidate? | preset/fixture/core-candidate/none |

A `core-candidate` answer is not a core change request by itself. It requires a
generic reproduction, standalone upstream test, and non-Bookshelf rationale
before any KOReader core work starts.

## Implementation Phases

### Phase 1: Manual Iteration

Use KOReader Profile only as the manual mechanism for applying a candidate
Reading Preset. Capture screenshots and KOReader Settings Snapshots by hand.

Promotion gate: each active starter fixture has complete render-case records
for the required Phase 1 matrix on `remarkable2-portrait`.

| Fixture source quality | Required Reading Preset IDs |
| --- | --- |
| clean publisher CSS | `koreader-default`, matching private default candidate |
| publisher CSS stress | `koreader-default`, `publisher-css-recovery` |
| broken line height | `koreader-default`, `publisher-css-recovery` |

Each promoted render case must include a manifest record that references the
full page screenshot, Status Bar/Footer crop, KOReader Settings Snapshot, Visual
QA Note, KOReader commit, plugin commit, fixture ID, Reading Preset ID, device
target, and page anchor.

Validation command:

```sh
python3 tools/reading_preset_qa.py validate \
  --captures doc/captures \
  --require-captures
```

Until this command passes, Phase 1 captures are evidence for review only and
cannot be called machine-validated.

### Phase 2: Reading Preset to KOReader Profile Export/Apply Path

Add a Bookshelf-owned export/apply path only after the preset values settle.
The plugin may use private Reading Preset vocabulary, but any KOReader-facing
settings must map through existing KOReader Profile and setting names. No new
KOReader install surface exists unless it is proposed separately upstream.

Promotion gate: the export/apply path can recreate the same KOReader Settings
Snapshot as the manual preset.

### Phase 3: KOReader Settings Import/Export Proposal

Propose a KOReader core surface only after the plugin proves a generic need
that is not specific to reMarkable or Bookshelf taste. Name the surface by the
generic KOReader operation it exposes, such as settings import/export or
KOReader Profile application. Do not propose a hook without a concrete
operation and standalone upstream use case.

Promotion gate: the upstream proposal has a standalone use case, tests, and no
dependency on this plugin's private screenshots.

## Upstream Notes

For KOReader core PRs, cite generic behavior, generic tests, and redacted
upstream reproduction bundles only. Keep private screenshots and Reading Preset
rationale in this plugin repo or private notes.

Private Bookshelf visual QA can inform our thinking, but it must not satisfy
KOReader upstream acceptance. Do not link this plugin doc as PR proof, and do
not add private Bookshelf screenshots to KOReader's user-facing README.

# KOReader Bookshelf UX

An experimental library/ebook reader-like home for KOReader on reMarkable
and other large e-ink devices. This replaces KOReader's file-browser as the default experience.

Status: working prototype. This is not an official KOReader project. I'm building this because I have several second-language books I want to read on a larger device (and I'm tired of kindle/apple books/remarkable enshittification).

<p>
  <img src="doc/images/bookshelf-horizontal-rails-remarkable-20260507.png" alt="KOReader Bookshelf horizontal book rails on reMarkable" width="320">
  <img src="doc/images/reader-progress-three-zone-remarkable-20260507.png" alt="KOReader Bookshelf reading view with three-zone footer on reMarkable" width="320">
</p>

## Goals

- Make your books the primary objects on launch.
- Keep the UX as fast as possible on e-ink: lazy integrations, fast first paint, cached book covers, and no network work on default home screen.
- Preserve KOReader's FileManager as an explicit secondary path, not a removed capability.
- Try my best to find a clean way to propose upstream changes back to KOReader if they'll consider it.

## Repository Layout

- `bookshelf.koplugin/`: KOReader plugin code for the Library surface.
- `integration/koreader/`: KOReader core integration files that are still best
  carried in a fork until a clean upstream hook exists.
- `spec/unit/`: unit tests for provider behavior, Home routing, and measurement
  helpers.
- `tools/`: measurement tooling for repeatable performance notes.
- `doc/`: manual QA, emulator notes, and evidence format.

## Local Development

This repo is developed against a KOReader checkout. The Lua code runs inside KOReader's own environment; host-global Lua is not required.

To try the plugin in a KOReader checkout, copy or link `bookshelf.koplugin/` to `plugins/bookshelf.koplugin` in that checkout, then apply the integration files from `integration/koreader/` to the matching KOReader paths.

From the KOReader checkout:

```sh
./kodev run
```

For a reMarkable-sized manual pass, use KOReader's emulator/noVNC workflow and set the emulator dimensions to 1404 x 1872 at 226 DPI. The current manual QA notes are in `doc/Bookshelf_prototype_measurement.md`.

## Verification

The current verification target is:

- Lua loads for the plugin and integration launcher.
- Busted specs for provider and Home routing behavior.
- Python unit tests for `tools/bookshelf_measure.py`.
- Manual visual QA in the SDL/noVNC emulator at reMarkable dimensions.
- Performance samples recorded through `tools/bookshelf_measure.py`.

Measurement helper examples:

```sh
python3 tools/bookshelf_measure.py scenarios
python3 tools/bookshelf_measure.py repeat \
  --iterations 10 \
  --device remarkable2 \
  --scenario first_visible_paint \
  --cache-state warm \
  --library-size 250
python3 tools/bookshelf_measure.py summarize
```

## License

KOReader is licensed under the GNU Affero General Public License. This prototype keeps the same license; see `COPYING`.

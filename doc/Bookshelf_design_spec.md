# Bookshelf Design Spec

## Typography

Bookshelf uses stock KOReader/reMarkable-compatible fonts by default.

- Noto Sans is the primary UI typeface.
- Noto Serif is the safe serif/display fallback in this prototype.
- EB Garamond can replace the display token only after it is bundled or verified
  in the KOReader runtime.
- Work Sans, Source Serif 4, and reMarkable Serif are not baseline dependencies.

Serif typography is reserved for library identity and large empty-state display
moments. Dense grids, metadata, controls, counts, and tab labels use Noto Sans.

## Type Scale

The library view uses a restrained modular ramp so section hierarchy comes from
weight and placement, not oversized labels. Dense book entries sit at 11-12,
category headers and controls share a 13px size, and the display title uses the
larger serif step.

| Use | Font | Size |
| --- | --- | ---: |
| Page title | Noto Serif Italic display fallback | 38 |
| Category header title | Noto Sans Bold | 13 |
| Category count and control labels | Noto Sans Regular | 13 |
| Category control values | Noto Sans Bold | 13 |
| Large grid title | Noto Sans Bold | 12 |
| Large grid metadata | Noto Sans Regular | 10 |
| Small grid title | Noto Sans Bold | 11 |
| Small grid metadata | Noto Sans Regular | 9 |
| Bottom tab labels | Noto Sans Regular/Bold active | 11 |
| Centered empty-state title | Noto Serif display fallback | 28 |
| Empty-state body | Noto Sans Regular | 14 |

## Font Coverage

EB Garamond is not used for small labels or dense grid text. Mixed-language and
CJK titles should rely on KOReader's Noto fallback stack, including Noto Sans CJK
where available.

## Bottom Tabs

The bottom tab bar is a persistent primary navigation component.

| Property | Value |
| --- | ---: |
| Height | 68 |
| Top padding | 10 |
| Bottom padding | 12 |
| Edge padding | 16 |
| Columns | 4 equal `1fr` slots |
| Top border | 1px light gray |
| Icon box | 24 x 24 |
| Icon-to-label gap | 5 |
| Label font | Noto Sans |
| Label size | 11 |
| Tap target | Full 1fr tab slot, minimum 68 high |

Active state uses a filled icon and primary text color. Inactive state uses
outline icons and secondary text color. Active and inactive labels use the same
size so the grid does not shift.

## Category Headers

Shelf/category headers use one component for Continue reading, Recently added,
and All books.

- Title, count, sort label, and sort value use the same 13px size.
- Title uses Noto Sans Bold.
- Count and control labels use Noto Sans Regular.
- Control values use Noto Sans Bold.
- Inline chevrons are icon components, not text glyphs, and align to the same
  title baseline as the category header.
- `View: Grid` is omitted until a list view exists.

## Spacing Tokens

Vertical spacing is shared by named layout tokens rather than shelf-specific
magic numbers.

| Token | Value |
| --- | ---: |
| Title to first shelf | 24 |
| Category header height | 30 |
| Header to shelf body | 12 |
| Continue to lower stack minimum | 28 |
| Recently added to All books | 32 |
| Lower stack bottom margin | 16 |

## Book Grid

Book covers use a fixed 2:3 portrait ratio in every shelf. Cards remain fixed
width and left-aligned; empty columns stay empty instead of stretching covers.

| Grid | Card | Cover | Cover ratio |
| --- | ---: | ---: | ---: |
| Large shelves | 148 x 284 | 148 x 222 | 2:3 |
| All books | 104 x 214 | 104 x 156 | 2:3 |

Both grid sizes use the same fixed 16px column gutter. If a viewport cannot fit
the maximum column count with that gutter, the grid uses fewer columns. It must
not compress spacing to force another book into the row.

The cover border wraps only the artwork/placeholder cover. Title, metadata, and
the menu icon sit underneath without a surrounding card border.

Card menu slots are 24px high in both grid sizes so the shared 24px icon fits
inside the card layout. Menu icons must not overflow into shelf or tab spacing.

## Screen Layout

The lower shelf stack is bottom-anchored above the persistent bottom tabs.
`Recently added` and `All books` move as one stack, with `All books` reserved as
a one-row shelf for now. Extra vertical space belongs to the `Continue reading`
region above that stack, up to the large-shelf card height. When the lower stack
needs room above the bottom tabs, the `Continue reading` region shrinks first.
The empty state uses that balanced body height instead of forcing lower shelves
into the tab area.

On cramped viewports, the lower stack may stop being pinned so it never overlaps
the `Continue reading` region.

## Icon System

Icons are rendered through `bookshelf.koplugin/icons.lua`. UI components should
request named icons instead of hand-drawing local symbol fragments. The shared
icon set owns stroke weight, active/inactive color, optical fill, and the
24-pixel visual icon box.

All app icons in the library view use the same 24px visual size: header
actions, inline chevrons, card menus, empty-state icons, and bottom tabs. Tap
targets may be larger than the visible glyph.

When KOReader already ships an appropriate SVG, the icon system maps the
bookshelf icon name onto KOReader's `IconWidget` asset pipeline. Custom
rect-based drawing is reserved for bookshelf-specific symbols or missing
assets. Section chevrons, header search, add, and files icons are all requested
through the same named icon API; section headers must not render text glyphs
such as `>`.

## Empty States

The Continue reading shelf has its own taller empty state. It should not reuse
the full-library empty message and should not render a dashed shelf placeholder.

| Element | Value |
| --- | ---: |
| Container body height | 284 |
| Container border | 1px light gray |
| Inner padding | 16 |
| Icon | Open book |
| Title | Nothing in progress yet |
| Body | Start reading a book and it will appear here. |

The icon, title, and body are centered as a quiet reading-progress prompt. The
container spans the shelf content width and uses the same inner padding as the
book-grid gutter.

## Placeholder Covers

Generated covers for books without artwork use a light e-ink gray base shade
inside the cover border. Placeholder covers use the same 2:3 dimensions as real
cover artwork. The title and metadata treatment remains unchanged.

---
name: MochiTunes
colors:
  surface: '#fff7fb'
  surface-dim: '#e8d4e9'
  surface-bright: '#fff7fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#ffeffe'
  surface-container: '#fce8fd'
  surface-container-high: '#f6e2f7'
  surface-container-highest: '#f0dcf1'
  on-surface: '#231726'
  on-surface-variant: '#574144'
  inverse-surface: '#392c3c'
  inverse-on-surface: '#ffebff'
  outline: '#8b7074'
  outline-variant: '#debfc2'
  surface-tint: '#ad2c4f'
  primary: '#ad2c4f'
  on-primary: '#ffffff'
  primary-container: '#ff6b8b'
  on-primary-container: '#6e0028'
  inverse-primary: '#ffb2bd'
  secondary: '#5a46c7'
  on-secondary: '#ffffff'
  secondary-container: '#7360e2'
  on-secondary-container: '#fffbff'
  tertiary: '#006b56'
  on-tertiary: '#ffffff'
  tertiary-container: '#18b191'
  on-tertiary-container: '#003c30'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffd9dd'
  primary-fixed-dim: '#ffb2bd'
  on-primary-fixed: '#400014'
  on-primary-fixed-variant: '#8c1038'
  secondary-fixed: '#e5deff'
  secondary-fixed-dim: '#c8bfff'
  on-secondary-fixed: '#190064'
  on-secondary-fixed-variant: '#442cb1'
  tertiary-fixed: '#77f9d5'
  tertiary-fixed-dim: '#57dcb9'
  on-tertiary-fixed: '#002018'
  on-tertiary-fixed-variant: '#005140'
  background: '#fff7fb'
  on-background: '#231726'
  surface-variant: '#f0dcf1'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 3.5rem
    fontWeight: '700'
    lineHeight: 4rem
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 2rem
    fontWeight: '700'
    lineHeight: 2.5rem
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 1.625rem
    fontWeight: '700'
    lineHeight: 2.125rem
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 1.5rem
    fontWeight: '600'
    lineHeight: 2rem
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 1.25rem
    fontWeight: '600'
    lineHeight: 1.75rem
  title-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 1.125rem
    fontWeight: '600'
    lineHeight: 1.5rem
  title-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 1rem
    fontWeight: '600'
    lineHeight: 1.375rem
  title-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 0.875rem
    fontWeight: '600'
    lineHeight: 1.25rem
  body-lg:
    fontFamily: Nunito Sans
    fontSize: 1rem
    fontWeight: '500'
    lineHeight: 1.5rem
  body-md:
    fontFamily: Nunito Sans
    fontSize: 0.875rem
    fontWeight: '500'
    lineHeight: 1.375rem
  body-sm:
    fontFamily: Nunito Sans
    fontSize: 0.75rem
    fontWeight: '500'
    lineHeight: 1.125rem
  label-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 0.875rem
    fontWeight: '700'
    lineHeight: 1.25rem
    letterSpacing: 0.01em
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 0.75rem
    fontWeight: '700'
    lineHeight: 1rem
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 0.6875rem
    fontWeight: '700'
    lineHeight: 0.875rem
    letterSpacing: 0.03em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-tablet: 1.5rem
  margin: 1rem
  margin-tablet: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system expresses a playful, comforting, and tactile mobile experience rooted in Material 3 guidelines. Designed for casual listeners, content archivers, and students who appreciate delightful, friendly utility tools, the aesthetic merges the warmth of Japanese stationery with the ergonomic clarity of Material You. 

The emotional tone balances reliability with joy: tactile controls feel cushiony and soft, transitions resemble gentle kinetic bounces, and audio progress feels lively rather than mechanical. Visuals avoid clinical corporate minimalism in favor of rounded, confectionery-inspired forms—squircle audio cards, pill-shaped tags, and creamy surfaces that feel inviting to tap.

Key stylistic pillars:
- **Tonal Comfort:** Dominant soft pastel blush surfaces accented by strawberry milk tones, preventing the glare of stark white backdrops.
- **Material 3 Expressiveness:** Full fidelity to M3 states, utilizing pill navigation indicators, tonal elevations, and squash-and-stretch tactile press responses.
- **Whimsical Utility:** Download queues, bit-rate switches, and audio visualizers incorporate cheerful iconography and rounded pill indicators without compromising operational clarity.

## Colors

The palette uses a confectionery harmony derived from Material 3 dynamic color science, anchored by strawberry milk pink, lavender mist, and refreshing mint.

- **Primary (`#FF6B8B`):** Strawberry Milk Pink. Directs focus to primary actions, active playback states, download triggers, and high-emphasis floating action buttons.
- **Secondary (`#8E7CFF`):** Periwinkle / Lavender. Applied to audio metadata tags, secondary category tabs, playlist badges, and media stream qualities (e.g., 320kbps MP3 / Opus toggles).
- **Tertiary (`#48CFAD`):** Fresh Mint. Reserved for active download completions, healthy network/converter statuses, and positive toggle states.
- **Neutral Surface / Text (`#FFF8F9` / `#2D2130`):** Base canvas is warm cream-blush (`#FFF8F9`), with nested card containers settling into a deeper blush (`#FCEEF2`). Text avoids cold black, using warm dark plum/charcoal (`#2D2130`) to retain organic warmth and high contrast.

### Surface Tiers & Container Roles
- `surface`: `#FFF8F9` (Screen canvas background)
- `surface-container-low`: `#FDF2F5` (Subtle grouped list background)
- `surface-container`: `#FCEEF2` (Standard song cards, bottom sheets)
- `surface-container-high`: `#F7E4EA` (Elevated modals, filter dialogs)
- `surface-container-highest`: `#EED7DF` (Sliders, active search track, progress backgrounds)
- `outline-variant`: `#F0CCD8` (Subtle separators, chip borders)

## Typography

Typography pairs `Plus Jakarta Sans` for titles, headers, and UI anchors with `Nunito Sans` for continuous reading, lyrics, and metadata. 

- **Headers & Labels:** `Plus Jakarta Sans` carries soft modern geometries with generous apertures, complementing pill buttons and squircle surfaces.
- **Body & Long Reads:** `Nunito Sans` lends warmth through rounded terminals, rendering track descriptions, format technicalities, and batch lists legible without visual fatigue.
- **Numbers & Media Counters:** Song durations (`03:42`), bitrates (`320 kbps`), and file sizes (`8.4 MB`) default to `label-md` with tabular numerals enabled to maintain alignment across reorderable download queues.

## Layout & Spacing

This system utilizes an 8-point base spatial rhythm adapted for fluid single-column mobile viewports and dual-pane tablet form factors.

- **Mobile Viewports (<600dp):** Fluid single column bounded by `16dp` (`margin`) outer edge paddings. Cards, track lists, and banners span edge-to-margin. Internal card paddings use `space-md` (16dp).
- **Tablet / Large Screens (≥600dp):** Converts into a split-pane structure (Left: library/navigation drawer, Right: active downloads and detail inspector) with `32dp` (`margin-tablet`) outer margins and `24dp` (`gutter-tablet`) column gaps.
- **Touch Targets:** All interactive icons (download buttons, grab handles, play toggles) respect a strict minimum touch target of `48×48dp`, using `space-xs` and `space-sm` for internal component padding.

## Elevation & Depth

Rather than harsh dropshadows, elevation relies on Material 3 tonal layering paired with soft, color-tinted ambient glows. 

- **Elevation Level 0 (Canvas):** Flat base surface at `#FFF8F9`.
- **Elevation Level 1 (Card Containers, Queues):** Surface tint `#FCEEF2`. Shadow: `0px 2px 8px rgba(45, 33, 48, 0.04)`.
- **Elevation Level 2 (Mini Player, Active Bottom App Bar):** Surface tint `#F7E4EA`. Shadow: `0px 4px 16px rgba(255, 107, 139, 0.12)`.
- **Elevation Level 3 (Bottom Sheets, URL Paste Modal):** Surface tint `#F3DDE4`. Shadow: `0px 8px 24px rgba(45, 33, 48, 0.08)`.
- **Elevation Level 4 (Floating Action Buttons & Badges):** Surface tint `#FF6B8B` (Primary). Shadow: `0px 6px 20px rgba(255, 107, 139, 0.28)`.
- **Elevation Level 5 (Drag State):** Applied to active `ReorderableListView` tiles when lifted; features an expanded strawberry halo: `0px 12px 28px rgba(255, 107, 139, 0.22)`, accompanied by a slight 1.02x scale.

## Shapes

The shape vocabulary defaults to level 3 ("Pill-shaped"), enforcing bubbly, welcoming aesthetics across both micro and macro components.

- **Cards & Sheets:** Heavy rounded surfaces (`24dp` to `28dp` border-radius) giving music cards and dialogs a cushion-like appearance.
- **Pills:** Full capsules (`999dp`) utilized for standard buttons, URL chips, filter tags, progress capsules, and the Flutter `NavigationBar` selection indicator.
- **Artwork Thumbnails:** Squircle cutouts with `16dp` border-radius to preserve image integrity while softening rectangular YouTube video thumbnails.
- **Sliders & Progress Indicators:** Fully rounded terminal caps with `8dp` track thickness for a tactile, playful scrubber bar.

## Components

### Buttons & Floating Action Buttons
- **Filled Button:** Height `48dp`, pill-shaped radius (`999dp`). Background `#FF6B8B`, foreground `#FFFFFF`. Light press ripple is tinted periwinkle.
- **Tonal Button:** Height `48dp`, background `#FCEEF2`, text/icon `#FF6B8B`.
- **Floating Action Button (FAB):** Expressive large M3 squircle FAB (`rounded-xl` or `28dp`), background `#FF6B8B`, icon color `#FFFFFF`. Features a bouncy, spring-based interaction when fetching video info from the clipboard.

### Navigation Bar
- Flutter M3 `NavigationBar` height `80dp`, background `#FFF8F9` with no top divider line; depth is created with tonal surface shifting.
- Active item indicator is a horizontal pill (`64×32dp`) colored in `#FCEEF2` with `#FF6B8B` icon and label. Inactive items use `#2D2130` at 60% opacity.

### Chips & Filter Pills
- Fully capsule-shaped (`999dp`), height `36dp`.
- **Input / URL Chip:** Soft blush container `#FCEEF2`, leading YouTube/Audio icon, trailing clear cross.
- **Filter Chips:** Inactive state features `#FCEEF2` background and `#2D2130` text. Selected state swaps to `#8E7CFF` (Lavender) with white text.

### Media Cards & Track Items
- Standard card uses a `24dp` border radius, `#FCEEF2` surface, and `12dp` internal padding.
- YouTube audio cards feature a `64×64dp` thumbnail with `16dp` rounded corners on the left, two lines of metadata (title in `title-md`, channel/bitrate in `body-sm`), and a trailing circular progress download button.

### Reorderable List Views & Drag Handles
- Track rows in download queues utilize pill-shaped drag handles positioned on the trailing side.
- Handle icon uses `#2D2130` at 40% opacity.
- While dragged, the active row scales up slightly (`1.02x`), gains elevation 5 with a soft pink ambient glow, and background lightens to `#FFFFFF`.

### Checkboxes, Radio Buttons & Switches
- **Switches:** Pill tracks with `#EED7DF` track color (inactive) and `#FF6B8B` (active). Thumb is oversized, circular, and ivory-white (`#FFFFFF`).
- **Radio / Checkbox:** Rounded square (`6dp` radius) checkboxes and circular radio marks in primary pink `#FF6B8B` with cream indicators.

### Input Fields (URL Bar & Search)
- Search and download URL bars are pill-shaped (`999dp` radius), height `56dp`, background `#FCEEF2`, with zero border lines.
- Placeholder text in `Nunito Sans` (`#2D2130` at 50% opacity). Leading paste icon and trailing batch download trigger.

### Badges & Download Status Indicators
- Status badges use pill shapes with `label-sm` bold text:
  - **Completed:** Mint container `#E4F9F3`, text `#168469`.
  - **Converting:** Lavender container `#EFEAFF`, text `#5C4AD9`.
  - **Downloading:** Pink container `#FFEBF0`, text `#FF6B8B` with animated horizontal striped progress capsule.
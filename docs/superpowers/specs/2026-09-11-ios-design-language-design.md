# Graphghan for iOS: design language ("Heather")

Status: approved in conversation on 2026-09-11; implementation plan to follow.
Canvas with every screen, sheet, and the explorations:
https://claude.ai/code/artifact/ab079b20-bc2f-4deb-a529-08175ee12c85

## 1. Goal and scope

Give the iOS app one visual system so every screen, the Live Activity, and the app icon read as
the same product, and so the palette can be swapped (dark mode, a per-pattern accent) without
touching layout or type. The app today is stock SwiftUI: system blue tint, system fonts, no icon.

In scope for the first build: the light theme on every screen, the Live Activity, the app icon,
the type ramp, and snapshot coverage. Out of scope: tuning and testing dark mode (its tokens are
declared, nothing more), a per-pattern accent, and user-facing theme settings.

## 2. Direction

The app is a neutral craft tool with a Scottish accent carried by material rather than
ornament: a stone ground with a faint tweed weave, deep moss for the one action, heather for
state. Each pattern's own yarn colors are the loudest thing on screen; the chrome stays quiet.

Sources that shaped it (research notes in the session, summarized):

- Ball bands, the barrel row counter, and the international stitch symbols (the chain oval,
  the sc cross) as crochet's own graphic language; the chain symbol became the icon.
- Fair Isle's discipline (two colors active per row, five or six in total) as the cap on how
  loud any one screen gets.
- Harris Tweed's "dyed in the wool" heather and sea colors for the state color.
- Ravelry's 2020 redesign as the cautionary tale: brighter and thinner cost accessibility. The
  ground is stone, not white; ink is charcoal-green, not black.
- From comparable apps: completed rows dim while the current row stays at full contrast, one
  accent reserved for state and action, the primary action on the first tap.

Two other directions were drawn and set aside: "Ball Band" (yarn-label utility, oatmeal and
printed charcoal, slab serif) and "Clicker" (dark-first, a recessed numeral window, one
stitch-marker pink). Clicker's warm dark neutrals were kept as the future dark palette.

## 3. Color

Seven semantic tokens, each a named color set in the asset catalog with a light and a dark
value. Code refers to tokens only; no view names a hex.

| Token | Role | Light | Dark (declared, untuned) |
|---|---|---|---|
| Ground | screen background; carries the weave | #EEEBE4 | #1B1917 |
| Panel | cards, the strip, list rows | #F8F6F1 | #262320 |
| Ink | primary text | #1F2A24 | #F1ECE2 |
| Ink 2 | secondary text | #5B675F | #A39C90 |
| Line | hairlines, borders | #D3D0C6 | #3A352F |
| Heather | state: current run, progress, selection | #7C5E8C | #C9A8DC |
| Moss | the one action: Done, primary buttons, tint | #1E4D3A | #2E7D5B |

Derived, not tokens: Moss Deep (#163B2D light) for the Back rail and the icon's hill band, which
is Moss darkened one step; Cream (#F4F5F0) for text on Moss; Brick (#9C3B3B) for the
save-failure rule.

Rules:

- Yarn colors from a chart are data, never tokens. Any yarn-colored surface (swatch, chip,
  palette entry, strip cell) draws its foreground with the existing light/dark rule in
  `HexColor.isLight` and a hairline at 14% black, so cream reads on cream.
- Moss is the app tint. System blue appears nowhere.
- Heather marks state (ring, bar, outline, marker). It never fills a button.
- The yellow and blue system banners are replaced (section 5.6).
- Contrast: every Ink 2 on Ground or Panel pairing is at or above 4.5:1; Cream on Moss is 8.8:1.

## 4. Texture

The weave is a repeating hairline at 135°, 1 point wide on a 5 point pitch, at 4.5% Ink on
Ground and 5% Cream on Moss. It is painted on Ground and on the Work screen's Moss field only.
Panels are flat so cards sit visibly on the weave without shadows; the Work card is the one
exception (section 5.1). In SwiftUI it is one view modifier drawing a tiled `Canvas` (or a
tiled image) behind the root of each screen.

## 5. Typography

### 5.1 Faces

| Role | Face | License | Used for |
|---|---|---|---|
| Display | Literata, semibold, optical size on | OFL | screen titles, row number, pattern and project titles, "Done" |
| Text | Atkinson Hyperlegible, regular and bold | OFL | everything else: body, labels, buttons, chips, codes |
| Numerals | Nunito Black | OFL | the big stitch count and any number that changes under the thumb |
| Marque | Metamorphous | OFL | pattern covers only; never in a text style that scales |

Files live under `ios/Fonts/` with their OFL texts and are registered in the app target's
Info.plist (`UIAppFonts`) via `project.yml`. The widget extension bundles no fonts.

### 5.2 Ramp

Every style is declared once, as a custom font relative to a system text style, so Dynamic Type
scales it and the accessibility sizes work. The Done label is a fixed size: it labels a field
that is already the target.

| Style | Face | Size | Relative to |
|---|---|---|---|
| Title | Literata 600 | 28 | largeTitle |
| Heading | Literata 600 | 22 | title2 |
| Row number | Literata 600 | 26 | title |
| Done | Literata 600 | 48 | fixed |
| Body | Atkinson 400 | 17 | body |
| Label | Atkinson 700 | 15 | subheadline |
| Caption | Atkinson 400 | 13 | footnote |
| Chip | Atkinson 700, tabular | 15 | subheadline |
| Count | Nunito 900, tabular | 84 | largeTitle, capped so it never wraps |
| Code | Atkinson 700 | 34 | title |

Rules: changing numbers use tabular figures; codes are bold Atkinson, not a monospace; no
uppercase letterspaced eyebrows. The Live Activity uses the same ramp in system faces: New York
semibold for display, SF Pro for text, SF Rounded heavy for the count.

## 6. Components

### 6.1 Work screen

Moss with the weave is the screen ground, and the whole ground is the Done target.

- Header on the green: close glyph at the leading edge, row number (Row number style) and the
  side line (Caption, 75% Cream) centered, all in Cream. Long press on the row number jumps.
- One stone card, 12 pt inset, 22 pt radius, Ground with the weave, drop shadow (0, 8) blur 24
  at 18% black. It holds the strip, the chips, and the swatch stack, 12 pt apart. The card
  swallows taps; nothing inside advances by accident.
- Strip: rows around the current one drawn from the grid in a Panel box with a Line border and
  14 pt radius; the current row outlined 2 pt Heather; rows already worked dimmed 45% toward
  black, upcoming rows at full contrast; a Heather marker on the starting edge.
- Chips: section 6.3.
- Swatch stack: the current run on top (Count, Code, and the color name in Heading, on its own
  yarn color, 16 pt radius); the next run on deck beneath it, 12 pt tucked under, in its own yarn
  color, reading "then 4 Charcoal" in Label. Last run in a row: the bar reads "next row starts in
  Gold". Last run of the pattern: no bar.
- Done field: everything below the card. "Done" in the Done style, centered in the field beside
  the rail. Tapping anywhere in the field advances. The Back rail sits on the leading edge of the field, 84 pt wide, Moss Deep,
  top trailing corner 22 pt, with the return arrow and "Back" in Label at 85% Cream. Swipe right
  anywhere still goes back.
- Finished: the card holds the strip and a Cream panel with a Line hairline, "Finished" in the
  Title style, and the send-off line in Body; the field reads "Close" and dismisses.
- Landscape keeps the same order in a two-column layout: card leading, field trailing.

### 6.2 Cards and list rows

Panel, 14 pt radius, one Line hairline, no shadow. Lists are plain with 12 pt between cards so
the weave shows between them. The project row: preview 96 × 80 at 10 pt radius with the yarn
hairline, title in Heading, a 6 pt Heather progress bar on 8% black, the row line
("Row 42 of 184 · 23%") and the estimate and last-worked lines in Caption, a chevron in Ink 2.
The pattern row is the same row without the bar. A finished project shows "Finished" in place of
the bar and row line.

### 6.3 Chips

Yarn color fill, pill, 36 pt tall, Chip text, the yarn hairline. Done runs at 35% opacity, the
current run with a 3 pt Heather ring. The same component lists the palette on the pattern
detail (code only, no ring), beside the color name in Label and the yarn note in Caption.

### 6.4 Buttons

Primary: Moss fill, Cream text in the Label style, pill, 50 pt tall. Secondary: Panel fill,
Line border, Moss text. Text buttons in Moss; destructive text in the system red inside sheets and
menus. Tint is Moss, so links and toolbar items follow.

### 6.5 Navigation

Standard tab bar and navigation stacks. Ground behind both, the weave on the screen behind the
list. Large titles in Literata through the navigation bar appearance. Tab items are SF Symbols,
Moss when selected and Ink 2 when not. No custom tab bar.

### 6.6 Banners and empty states

A banner is a Panel card with a 4 pt leading rule: Heather for information ("showing saved
patterns"), Brick for a save failure. Caption text, a Moss text button to dismiss or retry.
Empty states keep `ContentUnavailableView` with Moss tint, the title in Heading, the description
in Body.

### 6.7 Pattern detail

Back link in Moss, preview at 14 pt radius, title in Title, dedication in Body Ink 2, the quote
in Literata italic 17, a specs card (chart, finished size, stitch, version), the colors card
(6.3), instruction sections as cards, the published charts table, and "Start project" as the
primary button.

### 6.8 Live Activity

The lock screen card mirrors the Work card in system faces on the system dark material: title
(New York headline semibold) and "Row 42 of 184" (SF subheadline bold, 75% Cream) on one line;
the current run as a 44 pt swatch through the yarn-surface helper with the count in SF Rounded
heavy at 55% of the swatch height, beside the name (New York title3 semibold) and the next line
(SF footnote, 75% Cream); Back as a bordered capsule tinted 70% Cream, 44 × 40 pt; Done as a
Moss prominent capsule, 40 pt tall. These sizes are smaller than the canvas mockup because
Apple clips a lock-screen activity past 160 pt, and 12 pt padding plus a 44 pt swatch and 40 pt
buttons is what fits. The Dynamic Island keeps its current layout with the swatch and count.
Cream text throughout, on both the lock screen and the expanded island.

## 7. App icon

The PWA icon's composition, with the foundation chain in place of the stones:

- Moss sky with the weave (5% Cream), a Moss Deep hill band from 62% down.
- A Gold (#D9A21B) moon, radius 9%, centered at (74%, 30%).
- A chain of eight chevrons in Cream along the horizon, centered on the 62% line, 9.5% apart,
  stroke 6%, each with a 2% halo in Moss Deep so the stitches separate. Each chevron's tip sits
  3.5% behind its center and its arms reach 9.5% ahead and 8.5% to either side, so it reads as a
  crocheted chain stitch, the same shape as the blanket's braid border.

The 1024 pt master is generated by `ios/Scripts/make_icon.py` (`mise run icon` from `ios/`),
with every value expressed as a fraction of the side so `site/build.py`'s `make_icons` can adopt
the same geometry later (section 11). The
icon has no alpha; iOS applies its own mask.

## 8. Motion and haptics

One reveal: on Done, the current swatch slides up and off the card while the on-deck bar rises
into its place and the next bar slides in beneath, about 250 ms with the default spring; the
strip's outline moves to the new row on the same timing. Reduced motion turns the slide into a
crossfade. Everything else is a standard transition or none. Haptics are unchanged: light for a
run, medium for a row, a double tap when the next run introduces a color the previous row did
not use; Live Activity intents keep the system's feedback.

## 9. Implementation shape

- `Shared/Tokens.xcassets` and `Shared/Theme.swift`: the token color sets and their `Color`
  accessors plus the weave modifier, compiled into the app and the widget; `Shared/YarnSurface.swift`:
  the yarn-surface helper (fill, foreground, hairline) shared by swatch, chip, palette entry, and
  strip. `Graphghan/UI/Typography.swift`: the text styles as `Font.Heather` and the navigation and
  tab bar appearance.
- `Graphghan/UI/`: `Chip`, `Card`, `Banner`, `PrimaryButton` as small views used by every
  screen; the Work screen composes `WorkCard`, `SwatchStack`, and `DoneField`.
- `Shared/WorkActivityViews.swift`: the Live Activity views take the same tokens (colors only)
  and system faces.
- `project.yml`: font registration, the `AccentColor` set repointed to Moss, the icon set.
- The site's `styles.css` is not changed by this work.

## 10. Testing

- Snapshot tests in the existing harness (`Tests/Snapshots.swift`, iPhone 17 simulator): the
  Work screen mid-row, last run in row, and finished; the Projects list with one active and one
  finished project; the pattern detail; the existing Live Activity snapshots re-recorded.
- One Work screen snapshot at the largest accessibility size: the count may cap, nothing clips.
- A unit test of the yarn-surface helper with a cream-on-cream case, and a source-scanning
  guard test that fails on any hex literal, ad hoc `Color`, `.accentColor`, `.secondary`, or
  system text style in a view outside the token and helper files, so the rules above cannot
  drift.
- A unit test that the on-deck text is "then N Name", "next row starts in Name", or absent, per
  cursor position (pure, in the app target alongside `WorkFeedbackRule`).
- The manual pass in `ios/docs/qa.md` gains a "looks right" line per screen and the icon.

## 11. Later

- Dark mode: tune the declared values, name the theme (Ravelry names its themes after sheep
  breeds; the light theme is Heather), snapshot in dark.
- A per-pattern accent: one more token swap.
- Regenerate the PWA icon from the shared geometry so the site matches the app.

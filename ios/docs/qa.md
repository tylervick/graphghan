# Manual QA before a TestFlight build

Run on a real iPhone (Live Activities need the lock screen and Dynamic Island).

Run this on a device build (`ios/README.md`) before dispatching the TestFlight workflow.

## Work screen
- [ ] Open a project, tap Work, complete a full row with Done; the strip moves and the chips reset.
- [ ] Swipe right on the Done area, then on the chips: both step back exactly once.
- [ ] Long-press the row title and jump to row 40.
- [ ] Rotate mid-row; the layout survives and Done stays reachable.

## Live Activity
- [ ] With the Work screen open, lock the phone: the activity shows title, row of total, the current swatch, count, colour name, next run, Back and Done.
- [ ] Tap Done on the lock screen twice, then unlock: the Work screen shows the advanced cursor and the event log has two entries.
- [ ] Tap Back on the lock screen: the cursor steps back.
- [ ] Dynamic Island: compact shows swatch + count and R<row>; long-press shows the expanded card with the title, row, swatch, colour name, next-run line, and the Back and Done buttons.
- [ ] Close the Work screen: the activity ends.
- [ ] Finish the last run from the lock screen: the activity ends with "Finished".
- [ ] Kill the app while the activity is showing, then relaunch: the activity is refreshed to the stored cursor (or ended if the project was deleted).
- [ ] Settings › Graphghan › Live Activities off, open Work: the one-time hint appears with Open Settings.

## Looks right
- [ ] Home screen: the icon shows the moon, hill, and chain; it reads at the settings size too.
- [ ] Patterns and Projects: cards on the stone weave, Literata titles, Moss tab tint, no system blue anywhere.
- [ ] Pattern detail: quote in italic, palette chips with a visible edge on the cream chip, a Moss "Start project" pill.
- [ ] Work: green ground, the card does not advance when tapped, the on-deck bar shows the next run in its color, "next row starts in …" on the last run, Back rail steps back, Done slides the swatch.
- [ ] Work: the chip row shows the row's runs between the strip and the swatch, done runs dimmed, the current run ringed in heather, and a long row scrolls.
- [ ] Work at Settings › Accessibility › Larger Text (max): nothing overlaps the Done field.
- [ ] Reduce Motion on: the swatch crossfades instead of sliding.
- [ ] Lock screen activity: cream serif title, the swatch with its edge, capsule Back, Moss Done.

## Offline
- [ ] Airplane mode on the library (cached list + banner) and on a project (works normally).

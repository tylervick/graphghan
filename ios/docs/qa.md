# Manual QA before a TestFlight build

Run on a real iPhone (Live Activities need the lock screen and Dynamic Island).

Run this on a device build (`ios/README.md`) before dispatching the TestFlight workflow.

## Work screen
- [ ] Open a project, tap Work: the panel shows the run in its colour, the band shows the row at stitch scale with the row below underneath, the bar shows Back and a checkmark.
- [ ] Tap the panel, the band, and the capsule: each advances exactly one run. Swipe right: back.
- [ ] Row 42 of Craigh na Dun: the first eight runs show the braid sequence; run 11 (117 Cream) shows "0 of 117", the capsule reads "+10", each tap adds ten and the ring fills in; the ticks under the row read 10 … 110.
- [ ] Long-press the capsule: the step picker; choose "One tap per run": the capsule is a checkmark and one tap finishes the fill.
- [ ] Last run of a row, tap: the panel reads "Ch 1 in Gold, turn"; the capsule reads "Turned"; tap again: row 43.
- [ ] Long-press a stitch in the current row: the cursor jumps there.
- [ ] Pinch in on the band, or tap the row number: the whole chart, worked rows solid, row 42 a Heather line. Pinch out or tap again: the band.
- [ ] Long-press the row number and jump to row 40.
- [ ] Rotate mid-row; the band takes the trailing column and Back stays reachable.
- [ ] VoiceOver on the panel: it reads "Done with 7 single crochet in Cream", the value is "then 11 Purple", and the rotor offers Back, Jump to row, Jump within row, Choose counting step.
- [ ] Upgrade in place: install the current TestFlight build, work a few runs, install this build over it, open the project: the cursor and the event log survive and Sessions still adds up.

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
- [ ] Work: stone ground, the panel in the yarn colour, the band at 8 pt a stitch with the current run ringed in heather, capsules at the bottom; nothing says "Done".
- [ ] Work at Settings › Accessibility › Larger Text (max): nothing clips in the panel or the bar.
- [ ] Lock screen activity: cream serif title, the swatch with its edge, capsule Back, the Done capsule in the run's colour, Turned at a turn.

## Offline
- [ ] Airplane mode on the library (cached list + banner) and on a project (works normally).

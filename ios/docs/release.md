# Releasing to TestFlight

The release path is `.github/workflows/testflight.yml`. It runs in two ways:

- **On merge.** `ci.yml` calls it after its test jobs pass on a push to `main`. Its first job checks
  whether anything that goes into the binary (`ios/`, less `docs/`, `Tests/` and `Scripts/`) changed
  since the newest `ios-build-*` tag, and skips the archive otherwise. So a merge that changes the
  app ships a build; a docs-only, test-only or Python-only merge does not.
- **By hand.** Actions › TestFlight › Run workflow, for a dry run (`validate_only`) or a retry with
  an explicit `build_number`. A dispatch always ships.

Who gets a build is decided in App Store Connect, not here: the internal group has automatic
distribution on, so every processed build reaches the team without review; the external group has
it off, so an outside tester gets a build only when one is added to that group by hand (step 5 under
"Shipping a build"). Nothing in the workflow adds a build to a group.

## One-time setup

Done once per account/app; the state persists in the Apple developer portal, App Store Connect, and the repository secrets.

1. **App IDs.** `com.tylervick.graphghan` and `com.tylervick.graphghan.widgets`, both with the App Group capability and `group.com.tylervick.graphghan` assigned. Xcode's automatic signing created both on the first device build (`ios/README.md`, "Device build"); check in the portal under Identifiers.
2. **Distribution certificate.** The account's existing Apple Distribution certificate, exported as a `.p12`, is the same one Waddle's `BUILD_CERTIFICATE_BASE64` / `P12_PASSWORD` secrets hold. Reuse them (copy the values into this repository's secrets from the same source you set Waddle's from). If it has been renewed, export the new one and update both repositories.
3. **App Store profiles.** From `ios/`, with the App Store Connect key available (`Scripts/.appstore.env` defining `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`; the file is git-ignored):
   ```bash
   Scripts/asc-profiles.sh
   ```
   It creates or downloads "Graphghan App Store CI" and "Graphghan Widgets App Store CI" into `ios/build/profiles/` and prints the two `gh secret set` commands for `PROVISIONING_PROFILE_APP_BASE64` and `PROVISIONING_PROFILE_WIDGETS_BASE64`. The names must stay identical in `project.yml`, `ExportOptions-ci.plist`, and the portal.

   The profiles are bound to the account's single **unexpired** Apple Distribution certificate (expiry is read from the API, not from Apple's status string). If the account holds more than one, the script refuses to guess: it lists each candidate's id, name, and expiry and asks you to re-run as `ASC_CERT_ID=<id> Scripts/asc-profiles.sh`, choosing the certificate whose private key the `BUILD_CERTIFICATE_BASE64` p12 holds. Profiles expire with the certificate, so re-run the script after a renewal: an `ACTIVE` same-name profile is downloaded unchanged, while one left `EXPIRED` or `INVALID` by the renewal is deleted and recreated — Apple refuses to create a second profile under a name already in use, so replacing it is the only way the name survives.
4. **App Store Connect key.** Reuse Waddle's `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (base64 of the `.p8`). The key needs the App Manager role for the app.
5. **App record.** In App Store Connect, create the app "Graphghan" for bundle id `com.tylervick.graphghan` (platform iOS, SKU `graphghan`). `whats-to-test.sh` refuses to run until the record exists.
6. **TestFlight groups.** The internal group (team members) has "Enable automatic distribution" on: that is what makes a merge reach the team. Create an external group (for example "Crocheters") with it **off** and add the tester by email. The first build sent to an external group goes through Beta App Review (usually a day); later builds are available as soon as processing finishes. An internal tester can install builds without review.

Secrets checklist for `tylervick/graphghan`:

| secret | source |
|---|---|
| `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD` | same as Waddle |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` | same as Waddle |
| `PROVISIONING_PROFILE_APP_BASE64`, `PROVISIONING_PROFILE_WIDGETS_BASE64` | printed by `Scripts/asc-profiles.sh` |

## Shipping a build

1. Merge the change to `main`. If it touches app code, the `testflight` job of that push's CI run
   archives, uploads, pushes the `ios-build-N` tag, and attaches the What to Test notes. Confirm the
   build in App Store Connect; the run summary says why a green run is not proof by itself.
2. The notes are the derived changelog since the previous build, headed by the preamble in
   `ios/docs/whats-to-test.md` **only if that file changed since the previous build's tag**: a
   preamble is written for the next build, and the same text must not go out with every build
   after. Write it in the PR that ships the change (or merge it before that PR; on its own it does
   not trigger a build). Preview with `ios/Scripts/whats-to-test.sh --print`.
3. Build numbers are the newest `ios-build-*` tag plus one, whichever path runs, so the manual and
   the automatic path never collide. Runs serialize on one concurrency group.
4. Before an external release, run the manual checks in `ios/docs/qa.md` on a device build.
5. In App Store Connect › TestFlight, add the build to the external group. It is not set to
   auto-distribute, on purpose.

Manual path: Actions › TestFlight › Run workflow on `main`. Tick `validate_only` for a dry run (no
build number consumed). Leave `build_number` empty unless retrying a release whose upload succeeded
but whose tag did not land.

## When something fails

- Signing: "No Apple Distribution identity" means the p12 secret lacks its private key or the certificate expired. Regenerate the p12 and the profiles.
- Export: 'No "iOS App Store" profiles ... matching' means a profile name drifted between `project.yml`, `ExportOptions-ci.plist`, and the portal, or the widget profile secret is missing.
- Tag or notes failed after the upload: the build IS uploaded. Do not re-run; follow the message in the log (tag by hand, or set the notes in App Store Connect). Tag promptly: the next merge derives its build number from the newest tag, and without this one it would reuse the number App Store Connect already has.
- The `testflight` job of a CI run was skipped: its `decide` job found nothing under `ios/` (less docs, tests, scripts) changed since the newest tag, or a test job failed. The job's log says which.
- Distribution logs are attached as the `xcdistributionlogs` artifact on failure.

## TestFlight feedback

`.github/workflows/testflight-feedback.yml` runs every 30 minutes. It only names the bundle id and
the schedule: the importer itself lives in
[tylervick/testflight-feedback](https://github.com/tylervick/testflight-feedback), which three apps
share, and is pinned there by commit sha. Each TestFlight screenshot submission or crash
submission becomes one issue labelled
`bug`, `ios`, and `testflight-feedback`, with the comment, build number, device, OS, locale, the
screenshots, or the crash log collapsed. Screenshots are assets on the `testflight-feedback`
pre-release (stable URLs; Apple's expire). The tester's email is never read; the repo is public.

An issue is never opened twice: the importer lists issues by the `testflight-feedback` label and
reads the `<!-- testflight-feedback:<id> -->` marker each body ends with. Deleting an issue makes
the next run recreate it; close it instead.

Tell the tester: **take a screenshot inside the app and choose "Share Beta Feedback"**; after a
crash, TestFlight asks on its own.

To see what a run would do without opening anything, Actions › TestFlight feedback › Run workflow
with `dry_run` ticked, or locally with the keychain credentials:

```bash
ios/Scripts/with-asc-credentials.sh \
    ~/repos/testflight-feedback/scripts/testflight-feedback.sh \
    --bundle-id com.tylervick.graphghan --dry-run
```

Run it from this checkout: without `--repo`, the importer opens issues in whatever repository the
working directory belongs to.

The first real run imports every submission App Store Connect still holds (up to 50 of each kind),
so run a dry run first if the app has been on TestFlight for a while.

`asc-jwt.sh` exists in both repositories. This one is used by the release path
(`upload.sh`, `whats-to-test.sh`); the importer carries its own copy, so a change here does not
reach it.

Scheduled workflows are best-effort: GitHub may delay or skip a run under load, and it disables a
repository's schedules after 60 days with no activity, so re-enable it from the Actions tab if the
import goes quiet. When a scheduled import fails, look at Actions › TestFlight feedback › the
failed run's log; the next run picks up where it stopped, because created issues are already
tracked. A large first import (dozens of submissions) may hit GitHub's secondary rate limit and end
red part-way through; that is expected, and the next run finishes it. `gh release create` also
creates a git tag named `testflight-feedback`; it is harmless and unrelated to the `ios-build-*`
tags.

## Local archive

`ios/Scripts/archive.sh` with no environment produces a Release archive with automatic signing (`ExportOptions.plist`) and needs a signed-in Xcode; the project's Release config uses the manual profile names, so install both profiles in Xcode first (Settings › Accounts › Download Manual Profiles). `ios/Scripts/upload.sh --validate` validates the IPA with the API key.

## Building on the mini

The M1 mini can build, debug on a real device, and ship TestFlight without a laptop, driven from a phone over the tailnet. The host side lives in pewter (ADR-0019, `mini/orca-host.sh`); this section is the part that lives here.

### Credentials on the mini

The mini does **not** need the seven secrets `testflight.yml` sets. Four of them (`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, both `PROVISIONING_PROFILE_*_BASE64`) exist only to build an ephemeral keychain on a throwaway runner. The mini's keychain is persistent: the distribution certificate is imported once and `codesign` finds it by identity, and the two profiles live in `~/Library/MobileDevice/Provisioning Profiles/`.

Three values remain secret, seeded once into the build account's **login** keychain, which auto-unlocks at auto-login so an unattended upload does not block:

| Keychain service | Holds |
|---|---|
| `graphghan-asc-key-id` | the App Store Connect key id, e.g. `ABCD1234EF` |
| `graphghan-asc-issuer-id` | the issuer id (a UUID) |
| `graphghan-asc-private-key` | the `.p8` contents, `BEGIN`/`END` lines included |

Seed them as the build account:

```
security add-generic-password -a "$USER" -s graphghan-asc-key-id      -w 'ABCD1234EF'
security add-generic-password -a "$USER" -s graphghan-asc-issuer-id   -w '<issuer-uuid>'
security add-generic-password -a "$USER" -s graphghan-asc-private-key -w "$(cat AuthKey_ABCD1234EF.p8)"
```

Then run any release script through the wrapper, which exports `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` and materialises the `.p8` into a private temp directory that it deletes on exit:

```
ios/Scripts/with-asc-credentials.sh ios/Scripts/upload.sh --validate build/export/Graphghan.ipa
```

`archive.sh`, `upload.sh`, and `asc-profiles.sh` are unchanged by this — the wrapper only supplies the environment they already read, so CI and the mini run the same scripts.

Rotating any of the three means re-seeding the keychain **and** updating the repository secrets: they are separate copies of the same credential.

### The device lane

`ios/Scripts/check-device-available.sh` resolves the paired iPhone before a task tries to use it. It distinguishes three outcomes, because the phone being absent is normal rather than broken:

| Exit | Meaning | What a caller should do |
|---|---|---|
| `0` | a connected iOS device; prints `device: <name> (<udid>)` | build for the device |
| `3` | `GRAPHGHAN_DEVICE_UNAVAILABLE` — nothing connected | fall back to the simulator **and say so in the output** |
| `1` | devicectl failed, or a named device is absent while others are connected | stop; retrying will not help |

Exit 3 is deliberately not exit 1: a broken toolchain must never be mistaken for "no phone today", or device testing would stop silently while every run still looked green. Equally, asking for a specific device and getting a different one is treated as a fault, not a match — building on whichever phone happens to be attached is worse than not building.

Discovery is Bonjour/mDNS over the LAN and the tailnet does not carry mDNS, so the device lane works when you are home, not from anywhere. The phone must be unlocked, and stays on release iOS: a beta Xcode builds for a release device fine, while the reverse needs DeviceSupport workarounds.

### Pinning a different Xcode

Xcodes on the mini are installed side by side with `xcodes`, and a worktree can pin one without touching the global `xcode-select` that the release lane follows:

```
GRAPHGHAN_XCODE=/Applications/Xcode-beta.app orca worktree create --name xcode-beta ...
```

`orca.yaml`'s setup hook writes `ios/mise.local.toml` (gitignored) with `DEVELOPER_DIR`, so the pin lives and dies with that worktree. Nothing in the release path may add `-allowProvisioningUpdates`: automatic signing on a runner mints an Apple Distribution certificate whose key dies with the runner, against a per-account cap. Release stays `CODE_SIGN_STYLE: Manual`.

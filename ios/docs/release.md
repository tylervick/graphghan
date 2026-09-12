# Releasing to TestFlight

The release path is `.github/workflows/testflight.yml`, dispatched by hand. Nothing ships on a push or a tag.

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
6. **TestFlight group.** Create an external group (for example "Crocheters") and add the tester by email. The first build sent to an external group goes through Beta App Review (usually a day); later builds are available as soon as processing finishes. An internal tester (a user on the team) can install builds without review.

Secrets checklist for `tylervick/graphghan`:

| secret | source |
|---|---|
| `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD` | same as Waddle |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` | same as Waddle |
| `PROVISIONING_PROFILE_APP_BASE64`, `PROVISIONING_PROFILE_WIDGETS_BASE64` | printed by `Scripts/asc-profiles.sh` |

## Shipping a build

1. Run the manual checks in `ios/docs/qa.md` on a device build.
2. Optionally write a preamble in `ios/docs/whats-to-test.md` and merge it; preview the notes with `ios/Scripts/whats-to-test.sh --print`.
3. Actions › TestFlight › Run workflow on `main`. Tick `validate_only` for a dry run (no build number consumed). Leave `build_number` empty; the workflow derives it from the run number.
4. The run uploads the IPA as an artifact, uploads to App Store Connect, pushes the `ios-build-N` tag, and attaches the notes. Confirm the build in App Store Connect; the summary says why a green run is not proof by itself.
5. In App Store Connect › TestFlight, add the build to the external group if it is not set to auto-distribute.

## When something fails

- Signing: "No Apple Distribution identity" means the p12 secret lacks its private key or the certificate expired. Regenerate the p12 and the profiles.
- Export: 'No "iOS App Store" profiles ... matching' means a profile name drifted between `project.yml`, `ExportOptions-ci.plist`, and the portal, or the widget profile secret is missing.
- Tag or notes failed after the upload: the build IS uploaded. Do not re-run; follow the message in the log (tag by hand, or set the notes in App Store Connect).
- Distribution logs are attached as the `xcdistributionlogs` artifact on failure.

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

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
   It creates or downloads "Graphghan App Store CI" and "Graphghan Widgets App Store CI" into `ios/build/profiles/` and prints the two `gh secret set` commands for `PROVISIONING_PROFILE_APP_BASE64` and `PROVISIONING_PROFILE_WIDGETS_BASE64`. The names must stay identical in `project.yml`, `ExportOptions-ci.plist`, and the portal. Profiles expire with the certificate; re-run the script after a renewal. The script fails when the account holds more than one unexpired Distribution certificate, so the operator picks the right one by id.
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

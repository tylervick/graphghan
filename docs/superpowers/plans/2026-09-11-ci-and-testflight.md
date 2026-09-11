# CI and TestFlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every pull request runs the iOS core and app tests on a macOS runner, and a manually dispatched workflow archives, signs, and uploads a build to TestFlight with What-to-Test notes.

**Architecture:** A new `ios` job in `ci.yml` (path-filtered by a cheap ubuntu job) selects Xcode 26.2, installs the mise-pinned tools, runs `swift test` for the core package, the shell-script test suite, and `xcodebuild test` on the iPhone 17 simulator with the snapshot tests in a render-only mode (the pixel references are pinned to a local simulator OS, so CI verifies that every layout renders and uploads the renders as an artifact for eyeballing). Release signing is manual and lives in `project.yml`'s Release config and `ExportOptions-ci.plist`; `Scripts/archive.sh`, `upload.sh`, `asc-jwt.sh`, and `whats-to-test.sh` are adapted from Waddle and unit-tested hermetically; `testflight.yml` wires them together with an ephemeral keychain, both provisioning profiles, an IPA artifact, an `ios-build-N` tag, and notes attached through the App Store Connect API. A helper script creates the two App Store profiles through the same API so the portal work is one command plus the App Store Connect app record.

**Tech Stack:** GitHub Actions (`macos-26`, Xcode 26.2), mise, xcodegen 2.46, xcodebuild, `security`, `altool`, App Store Connect REST API v1 via curl + openssl ES256 JWT, bash 3.2-compatible scripts, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-10-graphghan-ios-app-design.md` §8 (repository, CI, TestFlight), §9 (testing), §11 (success criteria). This is "Plan 4: CI and TestFlight" from §10. Plans 1–3 are on `main`.

## Global Constraints

- Work on branch `feat/ci-testflight` in a worktree; never commit directly to `main`; the branch finishes as a pull request.
- Identifiers (spec §8.2): app `com.tylervick.graphghan`, extension `com.tylervick.graphghan.widgets`, App Group `group.com.tylervick.graphghan`, team `352UZEKYPP`, Xcode 26.2, iOS 17.0 deployment target, Swift 6 language mode.
- CI (spec §8.4): a new `ios` job in `.github/workflows/ci.yml` on `macos-26`, path-filtered to `ios/**`, `fixtures/**`, `schema/**` (plus the workflow file itself); install tools via mise, run xcodegen, `swift test` in the core package, then `xcodebuild test` for the app scheme on an iPhone simulator. Xcode pinned to 26.2.
- TestFlight (spec §8.5): `workflow_dispatch` only with `validate_only` and `build_number` inputs; concurrency group `testflight`, no cancel; build number = offset + run number, validated first; ephemeral keychain with the Distribution p12 and both profiles installed to both profile directories, codesign partition list set; archive and export with the App Store Connect API key; upload the IPA as an artifact before uploading to App Store Connect; tag `ios-build-N`; attach What to Test notes from `git log` since the previous tag; collect distribution logs on failure with the key id scrubbed; delete the keychain always. Secrets reused from Waddle: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`. New: `PROVISIONING_PROFILE_APP_BASE64`, `PROVISIONING_PROFILE_WIDGETS_BASE64`. Not copied: the nightly gate, engine build, screenshots, feedback fetching.
- Manual signing on the release path is a safety property (automatic signing plus `-allowProvisioningUpdates` on a runner mints throwaway Distribution certificates); the archive step never passes `-allowProvisioningUpdates`.
- Every GitHub Action is pinned to a commit SHA with a version comment (zizmor enforces it; `mise run pin-actions` verifies). `persist-credentials: false` on every checkout that does not push. `${{ }}` expressions never appear inside `run:` bodies; they go through `env:`.
- Scripts run under macOS `/bin/bash` 3.2: no associative arrays, `"${ARR[@]+"${ARR[@]}"}"` for possibly-empty arrays, `set -euo pipefail`, exit statuses tested rather than masked.
- Nothing in this plan commits or prints a secret. The `.p8`, `.p12`, and profile files never enter the repository; the implementer never runs `gh secret set` (the operator does, from the instructions in `ios/docs/release.md`).
- `hk check --all` (ruff, actionlint, zizmor, gitleaks, whitespace) and `uv run pytest -q` must stay green; from `ios/`, `mise run core-test`, `mise run script-test`, and `mise run test` must stay green.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_016acqd28TPss8NPKVWwzMxK`.

---

## File structure

| path | responsibility |
|---|---|
| `.github/workflows/ci.yml` | existing Python job unchanged; new `ios-changes` (path filter) and `ios` jobs |
| `.github/workflows/testflight.yml` | manual release workflow |
| `ios/Scripts/check-simulator-available.sh` | guard against the cold-runner simulator enumeration race |
| `ios/Scripts/asc-jwt.sh` | ES256 JWT for the App Store Connect API (verbatim from Waddle) |
| `ios/Scripts/archive.sh` | archive + export with print-only mode |
| `ios/Scripts/upload.sh` | altool upload/validate with the exit-0-error guard |
| `ios/Scripts/whats-to-test.sh` | derived changelog + attach via the API |
| `ios/Scripts/asc-profiles.sh` | create and download both App Store profiles via the API |
| `ios/Scripts/test-asc-jwt.sh`, `test-archive-args.sh`, `test-whats-to-test.sh`, `test-check-simulator.sh` | hermetic script tests |
| `ios/ExportOptions.plist`, `ios/ExportOptions-ci.plist` | local automatic / CI manual export options |
| `ios/project.yml` | Release config: manual signing, profile specifiers |
| `ios/mise.toml` | `script-test` task, `ci-test` task |
| `ios/Tests/Snapshots.swift` | `GRAPHGHAN_SNAPSHOTS` modes |
| `ios/docs/release.md` | portal one-time work, secrets, first build, Beta App Review |
| `ios/docs/whats-to-test.md` | optional hand-written preamble for the notes (starts empty) |
| `ios/README.md`, `README.md`, `ios/docs/qa.md` | notes |

---

### Task 0: Branch and worktree

- [ ] **Step 1: Create the worktree**

From the repo root:
```bash
git worktree add .worktrees/ci-testflight -b feat/ci-testflight main
cd .worktrees/ci-testflight && mise trust -q && mise install -q && mise run setup
cd ios && mise install -q && mise run core-test
```
Expected: 57 core tests green. All later commands run inside `.worktrees/ci-testflight`.

---

### Task 1: Snapshot modes and the simulator guard

**Files:**
- Modify: `ios/Tests/Snapshots.swift`
- Create: `ios/Scripts/check-simulator-available.sh`, `ios/Scripts/test-check-simulator.sh`
- Modify: `ios/mise.toml`

**Interfaces:**
- Produces: `Snapshots.Mode` (`compare` default, `render`, `record`) read from the process environment key `GRAPHGHAN_SNAPSHOTS`; output directory from `GRAPHGHAN_SNAPSHOT_OUT` (default: the `__Snapshots__` directory). xcodebuild forwards `TEST_RUNNER_GRAPHGHAN_SNAPSHOTS` and `TEST_RUNNER_GRAPHGHAN_SNAPSHOT_OUT` into the test host. `check-simulator-available.sh <device-name> <os-version>` exits 0 when the pair is enumerated, prints `GRAPHGHAN_SIMULATOR_UNAVAILABLE` when CoreSimulator enumerated nothing. mise tasks `script-test` and `ci-test`.

Semantics of the modes: `compare` is today's behaviour (record-then-fail-once when a reference is missing, pixel diff otherwise). `render` renders the view, writes `<name>.png` into the output directory, checks the size against the reference when one exists, and never compares pixels; a missing reference is not an error in this mode. `record` overwrites the reference and returns true (so a whole re-record is one run instead of delete-then-run-twice).

- [ ] **Step 1: The failing test for the modes**

Add to `ios/Tests/WorkActivityViewsTests.swift` (inside the suite):
```swift
    @Test func renderModeWritesIntoTheOutputDirectoryWithoutComparing() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)", isDirectory: true)
        let env = ["GRAPHGHAN_SNAPSHOTS": "render", "GRAPHGHAN_SNAPSHOT_OUT": out.path]
        // A view that would fail a pixel comparison against lock-midway: same size, different content.
        let ok = try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.lastInRow), named: "lock-midway",
                                      size: CGSize(width: 360, height: 170), environment: env)
        #expect(ok)
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("lock-midway.png").path))
        try? FileManager.default.removeItem(at: out)
    }

    @Test func renderModeStillCatchesASizeMismatch() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)", isDirectory: true)
        let env = ["GRAPHGHAN_SNAPSHOTS": "render", "GRAPHGHAN_SNAPSHOT_OUT": out.path]
        let ok = withKnownIssue("size mismatch is reported in render mode") {
            try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.midway), named: "lock-midway",
                                 size: CGSize(width: 360, height: 200), environment: env)
        }
        #expect(ok == nil || ok == false)
        try? FileManager.default.removeItem(at: out)
    }
```
(`withKnownIssue` returns the body's value when no issue was recorded and nil when one was, so both branches are asserted; if the SDK's `withKnownIssue` signature does not return the value, replace the second test's body with a direct call inside `withKnownIssue { _ = try ... }` and drop the `#expect(ok ...)` line, noting it.)

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && mise run test` → compile error: `assert(_:named:size:environment:)` does not exist.

- [ ] **Step 3: Implement the modes**

Replace the body of `ios/Tests/Snapshots.swift` from `enum Snapshots {` through the end of `assert` with:
```swift
@MainActor
enum Snapshots {
    enum Mode: String { case compare, render, record }

    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        return url.appendingPathComponent("__Snapshots__", isDirectory: true)
    }()

    /// GRAPHGHAN_SNAPSHOTS selects the mode; GRAPHGHAN_SNAPSHOT_OUT the directory renders go to in `render` mode.
    /// xcodebuild forwards TEST_RUNNER_-prefixed variables into the test host, which is how CI sets them.
    static func mode(_ environment: [String: String]) -> Mode {
        Mode(rawValue: environment["GRAPHGHAN_SNAPSHOTS"] ?? "") ?? .compare
    }

    static func outputDirectory(_ environment: [String: String]) -> URL {
        if let path = environment["GRAPHGHAN_SNAPSHOT_OUT"], !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return directory
    }

    /// Returns true when the rendering matches the reference (compare), was written (record), or rendered at the
    /// reference size (render). Records and returns false when a reference is missing in compare mode.
    static func assert(_ view: some View, named name: String, size: CGSize, tolerance: Double = 0.005,
                       environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData() else { throw SnapshotError.renderFailed(name) }
        let reference = directory.appendingPathComponent("\(name).png")
        let mode = mode(environment)

        switch mode {
        case .record:
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: reference)
            return true
        case .render:
            let out = outputDirectory(environment)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try png.write(to: out.appendingPathComponent("\(name).png"))
            guard FileManager.default.fileExists(atPath: reference.path),
                  let expected = UIImage(data: try Data(contentsOf: reference))?.cgImage, let actual = image.cgImage else { return true }
            guard expected.width == actual.width, expected.height == actual.height else {
                Issue.record("\(name): size \(actual.width)x\(actual.height) != \(expected.width)x\(expected.height)")
                return false
            }
            return true
        case .compare:
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: reference.path) else {
                try png.write(to: reference)
                Issue.record("Recorded new snapshot \(name).png; re-run to compare.")
                return false
            }
            guard let expected = UIImage(data: try Data(contentsOf: reference))?.cgImage, let actual = image.cgImage else { throw SnapshotError.renderFailed(name) }
            guard expected.width == actual.width, expected.height == actual.height else {
                try png.write(to: directory.appendingPathComponent("\(name).actual.png"))
                Issue.record("\(name): size \(actual.width)x\(actual.height) != \(expected.width)x\(expected.height)")
                return false
            }
            let diff = differingFraction(expected, actual)
            if diff > tolerance {
                try png.write(to: directory.appendingPathComponent("\(name).actual.png"))
                Issue.record("\(name): \(Int(diff * 1000)) per mille of pixels differ (see \(name).actual.png)")
                return false
            }
            return true
        }
    }
```
Keep `pixels`, `differingFraction`, and `SnapshotError` as they are. Update the file's doc comment to name the three modes.

- [ ] **Step 4: The simulator guard and its test**

`ios/Scripts/check-simulator-available.sh` (adapted from Waddle; the marker is renamed):
```bash
#!/bin/bash
# Confirms a named iOS Simulator device/OS pair is genuinely available before a build spends the
# whole run against it. On a cold macOS runner CoreSimulator sometimes enumerates NO devices at
# all for the first minute; xcodebuild then fails ~60s in with "Unable to find a device matching
# the provided destination specifier". That is infrastructure, not the code under test, and a
# re-run fixes it -- so this guard retries, and distinguishes "nothing enumerated" (prints the
# GRAPHGHAN_SIMULATOR_UNAVAILABLE marker: re-run the job) from "devices enumerated but none match"
# (a genuine destination pin problem: a re-run will not help).
#
# Usage: ios/Scripts/check-simulator-available.sh <device-name> <os-version>
#   e.g. ios/Scripts/check-simulator-available.sh "iPhone 17" 26.2
# SIMULATOR_CHECK_ATTEMPTS / SIMULATOR_CHECK_DELAY (seconds) override the schedule; the test sets
# the delay to 0. SIMCTL overrides the `xcrun simctl` command so the test can feed fixtures.
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <device-name> <os-version>" >&2
    exit 2
fi
DEVICE_NAME="$1"
OS_VERSION="$2"
ATTEMPTS="${SIMULATOR_CHECK_ATTEMPTS:-5}"
DELAY="${SIMULATOR_CHECK_DELAY:-15}"
SIMCTL="${SIMCTL:-xcrun simctl}"

listing=""
total_count=0
match_line=""

query_once() {
    # A failing simctl is the same infrastructure signal as an empty enumeration; do not mask it.
    if listing="$($SIMCTL list devices available 2>&1)"; then
        :
    else
        listing=""
    fi
    total_count="$(printf '%s\n' "$listing" | grep -cE '^    [^[:space:]]' || true)"
    # Exact match on the name inside the requested OS section. The name is recovered by peeling the two
    # trailing "(udid) (state)" fields off the right, because device names themselves may contain parentheses.
    match_line="$(printf '%s\n' "$listing" | awk -v os="$OS_VERSION" -v dev="$DEVICE_NAME" '
        /^-- / { insection = ($0 == "-- iOS " os " --"); next }
        insection && /^    / {
            line = $0
            sub(/^    /, "", line)
            sub(/[[:space:]]+$/, "", line)
            name = line
            sub(/ \([^()]*\)$/, "", name)
            sub(/ \([^()]*\)$/, "", name)
            if (name == dev) { print line; exit }
        }
    ')"
}

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
    query_once
    if [ -n "$match_line" ]; then
        echo "matched: $match_line (iOS $OS_VERSION, attempt $attempt/$ATTEMPTS)"
        exit 0
    fi
    if [ "$attempt" -lt "$ATTEMPTS" ]; then
        sleep "$DELAY"
    fi
    attempt=$((attempt + 1))
done

if [ "$total_count" -eq 0 ]; then
    echo "::error::GRAPHGHAN_SIMULATOR_UNAVAILABLE -- CoreSimulator enumerated zero simulators after $ATTEMPTS attempts. Runner infrastructure, not the code under test: re-run the job."
else
    echo "::error::requested simulator not found: '$DEVICE_NAME' (iOS $OS_VERSION) -- $total_count other device(s) enumerated. A genuine destination pin problem; re-running will not fix it."
fi
echo "requested: name=\"$DEVICE_NAME\" OS=$OS_VERSION"
printf '%s\n' "$listing"
exit 1
```
`ios/Scripts/test-check-simulator.sh`:
```bash
#!/bin/bash
# Hermetic tests for check-simulator-available.sh: SIMCTL points at a stub that prints a fixture.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

stub() { # fixture-text -> path of a stub simctl
    printf '#!/bin/bash\ncat <<'"'"'FIX'"'"'\n%s\nFIX\n' "$1" > "$TMP/simctl"
    chmod +x "$TMP/simctl"
    echo "$TMP/simctl"
}
LISTING='== Devices ==
-- iOS 26.2 --
    iPhone 17 (0A1B2C3D-0000-0000-0000-000000000001) (Shutdown)
    iPhone 17 Pro (0A1B2C3D-0000-0000-0000-000000000002) (Shutdown)
    iPad Pro 13-inch (M4) (0A1B2C3D-0000-0000-0000-000000000003) (Shutdown)
-- iOS 18.5 --
    iPhone 16 (0A1B2C3D-0000-0000-0000-000000000004) (Shutdown)'

run() { SIMULATOR_CHECK_DELAY=0 SIMULATOR_CHECK_ATTEMPTS=2 SIMCTL="$1" "$HERE/check-simulator-available.sh" "$2" "$3"; }

out="$(run "$(stub "$LISTING")" "iPhone 17" 26.2)" || fail "exact name should match: $out"
grep -q "matched: iPhone 17 (" <<<"$out" || fail "matched the wrong line: $out"
pass "exact device name in the requested OS section matches"

if run "$(stub "$LISTING")" "iPhone 1" 26.2 >"$TMP/o" 2>&1; then fail "a prefix must not match"; fi
grep -q "requested simulator not found" "$TMP/o" || fail "wrong diagnostic: $(cat "$TMP/o")"
! grep -q GRAPHGHAN_SIMULATOR_UNAVAILABLE "$TMP/o" || fail "marker printed for a pin problem"
pass "a name prefix does not match and the marker is not printed"

out="$(run "$(stub "$LISTING")" "iPad Pro 13-inch (M4)" 26.2)" || fail "parenthesised name should match: $out"
pass "device names containing parentheses match"

if run "$(stub "$LISTING")" "iPhone 17" 18.5 >"$TMP/o" 2>&1; then fail "wrong OS section must not match"; fi
pass "the OS section is respected"

if run "$(stub '== Devices ==')" "iPhone 17" 26.2 >"$TMP/o" 2>&1; then fail "empty enumeration must fail"; fi
grep -q GRAPHGHAN_SIMULATOR_UNAVAILABLE "$TMP/o" || fail "marker missing for an empty enumeration: $(cat "$TMP/o")"
pass "an empty enumeration prints the re-run marker"

printf '#!/bin/bash\nexit 1\n' > "$TMP/simctl"; chmod +x "$TMP/simctl"
if run "$TMP/simctl" "iPhone 17" 26.2 >"$TMP/o" 2>&1; then fail "a failing simctl must fail"; fi
grep -q GRAPHGHAN_SIMULATOR_UNAVAILABLE "$TMP/o" || fail "a failing simctl should read as infrastructure"
pass "a failing simctl is treated as infrastructure"
```
`chmod +x` both scripts. Add to `ios/mise.toml`:
```toml
[tasks.script-test]
description = "Hermetic tests for the shell scripts under Scripts/"
run = """
for t in Scripts/test-*.sh; do echo "== $t"; "$t"; done
"""

[tasks.ci-test]
description = "The app tests exactly as CI runs them: render-only snapshots into build/snapshots"
depends = ["generate"]
run = """
mkdir -p build/snapshots
TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=render TEST_RUNNER_GRAPHGHAN_SNAPSHOT_OUT="$PWD/build/snapshots" \
  xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -resultBundlePath build/TestResults.xcresult
"""
```
(`build/` is already git-ignored; `-resultBundlePath` must not already exist, so the task deletes `build/TestResults.xcresult` first: add `rm -rf build/TestResults.xcresult` as the first line of the run block.)

- [ ] **Step 5: Run everything**

Run from `ios/`: `mise run script-test` (6 ok lines), `mise run test` (58 tests, green), `mise run ci-test` (green; `ls build/snapshots` lists nine PNGs). Also confirm the `render` mode is really reached through xcodebuild: with the references present, temporarily rename `ios/Tests/__Snapshots__/lock-midway.png`, run `mise run ci-test` (must still pass), rename it back, and note the result in the report.

- [ ] **Step 6: Commit**

```bash
git add ios/Tests/Snapshots.swift ios/Tests/WorkActivityViewsTests.swift ios/Scripts/check-simulator-available.sh ios/Scripts/test-check-simulator.sh ios/mise.toml
git commit -m "test(ios): snapshot render/record modes and a simulator availability guard for CI"
```

---

### Task 2: The `ios` CI job

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `ios/Scripts/check-simulator-available.sh`, `ios/mise.toml` tasks `generate`, `core-test`, `script-test`; the snapshot env keys from Task 1.
- Produces: jobs `ios-changes` (output `run`) and `ios`; artifact `ios-snapshots` (render-only PNGs) and `ios-test-results` on failure.

- [ ] **Step 1: Add the jobs**

Append to `.github/workflows/ci.yml` after the `test` job (before `deploy`); keep the `deploy` job's `needs: test` unchanged so a skipped iOS job never blocks Pages:
```yaml
  # Cheap path filter so a docs-only or Python-only change never spins up a macOS runner.
  # `on.pull_request.paths` would filter the whole workflow, and the Python job must always run.
  ios-changes:
    runs-on: ubuntu-latest
    outputs:
      run: ${{ steps.filter.outputs.run }}
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with: {persist-credentials: false, fetch-depth: 0}
      - id: filter
        env:
          EVENT: ${{ github.event_name }}
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          BEFORE_SHA: ${{ github.event.before }}
        run: |
          if [ "$EVENT" = "pull_request" ]; then RANGE="$BASE_SHA...HEAD"; else RANGE="$BEFORE_SHA..HEAD"; fi
          # A force-push or a brand-new branch has no usable "before": run the job rather than skip it.
          if ! CHANGED="$(git diff --name-only "$RANGE" 2>/dev/null)"; then CHANGED="ios/"; fi
          if printf '%s\n' "$CHANGED" | grep -qE '^(ios/|fixtures/|schema/|\.github/workflows/ci\.yml)'; then
            echo "run=true" >> "$GITHUB_OUTPUT"; echo "iOS-relevant paths changed."
          else
            echo "run=false" >> "$GITHUB_OUTPUT"; echo "No iOS-relevant paths changed; skipping the ios job."
          fi

  ios:
    needs: ios-changes
    if: ${{ needs.ios-changes.outputs.run == 'true' }}
    runs-on: macos-26
    timeout-minutes: 45
    env:
      XCODE_VERSION: "26.2"
      SIMULATOR_DEVICE: iPhone 17
      SIMULATOR_OS: "26.2"
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with: {persist-credentials: false}
      - name: Select Xcode
        env:
          XCODE_VERSION: ${{ env.XCODE_VERSION }}
        run: |
          APP="/Applications/Xcode_${XCODE_VERSION}.app"
          if [ ! -d "$APP" ]; then
            echo "::error::$APP not found on this runner image. Installed:"; ls -d /Applications/Xcode*.app; exit 1
          fi
          sudo xcode-select -s "$APP"
          xcodebuild -version
      # mise installs the xcodegen version ios/mise.toml pins (the image ships none).
      - uses: jdx/mise-action@c37c93293d6b742fc901e1406b8f764f6fb19dac # v2.4.4
        with: {cache: true, working_directory: ios}
      - name: Core package tests
        working-directory: ios
        run: mise run core-test
      - name: Script tests
        working-directory: ios
        run: mise run script-test
      - name: Verify the simulator is available
        working-directory: ios
        env:
          SIMULATOR_DEVICE: ${{ env.SIMULATOR_DEVICE }}
          SIMULATOR_OS: ${{ env.SIMULATOR_OS }}
        run: Scripts/check-simulator-available.sh "$SIMULATOR_DEVICE" "$SIMULATOR_OS"
      - name: Generate the project
        working-directory: ios
        run: mise run generate
      # Snapshot references are pinned to a developer's simulator OS, so CI renders every layout
      # (and checks sizes) instead of comparing pixels; the renders are uploaded for eyeballing.
      - name: App tests (iPhone simulator)
        working-directory: ios
        env:
          DESTINATION: platform=iOS Simulator,name=${{ env.SIMULATOR_DEVICE }},OS=${{ env.SIMULATOR_OS }}
          TEST_RUNNER_GRAPHGHAN_SNAPSHOTS: render
          TEST_RUNNER_GRAPHGHAN_SNAPSHOT_OUT: ${{ runner.temp }}/snapshots
        run: |
          xcodebuild test -project Graphghan.xcodeproj -scheme Graphghan \
            -destination "$DESTINATION" -derivedDataPath build/DerivedData \
            -resultBundlePath "$RUNNER_TEMP/TestResults.xcresult" | tail -n 60
          test "${PIPESTATUS[0]}" -eq 0
      - name: Upload rendered snapshots
        if: always()
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7
        with:
          name: ios-snapshots
          path: ${{ runner.temp }}/snapshots
          if-no-files-found: ignore
          retention-days: 7
      - name: Upload test results
        if: failure()
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7
        with:
          name: ios-test-results
          path: ${{ runner.temp }}/TestResults.xcresult
          if-no-files-found: ignore
          retention-days: 7
```
If `jdx/mise-action` v2.4.4 has no `working_directory` input, drop it and instead run `mise install` inside the `Core package tests` step (`working-directory: ios`, `run: mise install -q && mise run core-test`); the root `mise.toml` still installs `uv`/`hk`. Record which.

- [ ] **Step 2: Lint the workflow**

Run from the repo root: `hk check --all` (actionlint and zizmor must pass; zizmor's template-injection rule is why every `${{ }}` sits in `env:`), then `mise run pin-actions` to verify the SHAs. Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: ios job runs the core, script, and simulator tests on macos-26"
```

The job is proven on the pull request itself (Task 7 opens it); the `ios-changes` filter must report `run=true` for this branch and the `ios` job must be green before the PR is merged.

---

### Task 3: Release signing configuration and `archive.sh`

**Files:**
- Modify: `ios/project.yml`
- Create: `ios/ExportOptions.plist`, `ios/ExportOptions-ci.plist`, `ios/Scripts/archive.sh`, `ios/Scripts/test-archive-args.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: profile names `Graphghan App Store CI` (app) and `Graphghan Widgets App Store CI` (extension) used identically by `project.yml`, `ExportOptions-ci.plist`, `asc-profiles.sh` (Task 5), and `release.md`. `archive.sh` env contract: `ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID` (all three or none), `BUILD_NUMBER`, `EXPORT_OPTIONS_PLIST` (default `ExportOptions.plist`), `ARCHIVE_PRINT_ONLY=1`; archive at `ios/build/archive/Graphghan.xcarchive`, IPA at `ios/build/archive/export/Graphghan.ipa`.

- [ ] **Step 1: The failing script test**

`ios/Scripts/test-archive-args.sh`:
```bash
#!/bin/bash
# archive.sh must assemble the right command lines AND survive with no CI env set: macOS /bin/bash
# is 3.2, where `set -u` on an empty array aborts unless expanded as "${ARR[@]+"${ARR[@]}"}".
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
BASH32=/bin/bash
"$BASH32" --version | head -1 | grep -q 'version 3\.2' || echo "warn: $BASH32 is not 3.2; the empty-array case may not be exercised"

run_archive() { env -u ASC_KEY_PATH -u ASC_KEY_ID -u ASC_ISSUER_ID -u BUILD_NUMBER -u EXPORT_OPTIONS_PLIST \
                    ARCHIVE_PRINT_ONLY=1 "$@" "$BASH32" "$HERE/archive.sh"; }

OUT="$(run_archive 2>&1)" || fail "archive.sh aborted with no env set: $OUT"
case "$OUT" in
  *-authenticationKey*) fail "auth flags present with no ASC env set" ;;
  *CURRENT_PROJECT_VERSION*) fail "version override present with no BUILD_NUMBER" ;;
esac
grep -q "ExportOptions.plist" <<<"$OUT" || fail "default export plist not used"
grep -q -- "-scheme Graphghan" <<<"$OUT" || fail "wrong scheme"
! grep -q -- "archive.*-allowProvisioningUpdates" <<<"$OUT" || fail "archive step must never pass -allowProvisioningUpdates"
pass "no env -> no auth flags, no version override, default plist, no provisioning updates on archive"

OUT3="$(ARCHIVE_PRINT_ONLY=1 ASC_KEY_PATH=/tmp/k.p8 ASC_KEY_ID=KEYID ASC_ISSUER_ID=ISSUER BUILD_NUMBER=42 \
        EXPORT_OPTIONS_PLIST=ExportOptions-ci.plist "$BASH32" "$HERE/archive.sh" 2>&1)" || fail "archive.sh failed with CI env set"
[ "$(grep -c -- '-authenticationKeyPath /tmp/k.p8' <<<"$OUT3")" -eq 2 ] || fail "auth flags must be on both xcodebuild lines"
grep -q -- 'CURRENT_PROJECT_VERSION=42' <<<"$OUT3" || fail "build number override missing"
grep -q -- 'ExportOptions-ci.plist' <<<"$OUT3" || fail "CI plist not used"
pass "CI env -> auth flags on both lines, build number override, CI plist"

OUT4="$(ARCHIVE_PRINT_ONLY=1 ASC_KEY_ID=KEYID "$BASH32" "$HERE/archive.sh" 2>&1)" || fail "partial ASC env failed"
case "$OUT4" in *-authenticationKey*) fail "auth flags added from partial env" ;; esac
pass "partial ASC env -> no auth flags"

if ASC_KEY_PATH=/tmp/k.p8 ASC_KEY_ID=K ASC_ISSUER_ID=I "$BASH32" "$HERE/archive.sh" >/dev/null 2>"$TMPDIR/err" ; then
  fail "ASC auth without an explicit manual plist must be refused"
fi
grep -q "manual-signing export plist" "$TMPDIR/err" || fail "refusal did not explain itself: $(cat "$TMPDIR/err")"
pass "ASC auth without EXPORT_OPTIONS_PLIST is refused before any work"
```
(The last case does not set `ARCHIVE_PRINT_ONLY`, so it exercises the real guard, which must fire before xcodegen or xcodebuild run.)

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && chmod +x Scripts/test-archive-args.sh && Scripts/test-archive-args.sh` → fails: `archive.sh` not found.

- [ ] **Step 3: Signing config**

In `ios/project.yml`, change the project-level `settings:` to:
```yaml
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    TARGETED_DEVICE_FAMILY: "1"
    # Same team as Waddle; xcodegen regenerates the project, so the team lives here, not in Xcode's pane.
    DEVELOPMENT_TEAM: 352UZEKYPP
  configs:
    Debug:
      CODE_SIGN_STYLE: Automatic
    # Manual on the release path is a safety property, not a preference: automatic signing plus
    # -allowProvisioningUpdates on a runner MINTS a new Apple Distribution certificate whose key dies
    # with the runner, and Apple caps those per account. The two profiles are manually managed in the
    # portal (Scripts/asc-profiles.sh creates them) and installed on the runner from secrets.
    Release:
      CODE_SIGN_STYLE: Manual
      CODE_SIGN_IDENTITY: "Apple Distribution"
```
Under the `Graphghan` target's `settings:` add:
```yaml
      configs:
        Release:
          # XcodeGen's application preset injects CODE_SIGN_IDENTITY=iPhone Developer at target scope,
          # which would shadow the project-level Apple Distribution under Manual signing.
          CODE_SIGN_IDENTITY: "Apple Distribution"
          PROVISIONING_PROFILE_SPECIFIER: "Graphghan App Store CI"
```
and under the `GraphghanWidgets` target's `settings:`:
```yaml
      configs:
        Release:
          CODE_SIGN_IDENTITY: "Apple Distribution"
          PROVISIONING_PROFILE_SPECIFIER: "Graphghan Widgets App Store CI"
```
`ios/ExportOptions.plist` (local, automatic):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Local use only: a signed-in Xcode resolves profiles itself. CI uses ExportOptions-ci.plist. -->
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>352UZEKYPP</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
```
`ios/ExportOptions-ci.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- CI-only. Manual signing is a safety property: with automatic signing plus
         -allowProvisioningUpdates, a missing identity makes xcodebuild MINT a new Apple Distribution
         certificate whose key dies with the runner. The profile names must match project.yml's
         Release PROVISIONING_PROFILE_SPECIFIER values exactly: archive and export resolve the profile
         independently, and a drifted name fails at export after a successful archive. Both profiles
         are installed on the runner from PROVISIONING_PROFILE_APP_BASE64 and
         PROVISIONING_PROFILE_WIDGETS_BASE64; they expire with the certificate they are bound to. -->
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>352UZEKYPP</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Apple Distribution</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.tylervick.graphghan</key>
        <string>Graphghan App Store CI</string>
        <key>com.tylervick.graphghan.widgets</key>
        <string>Graphghan Widgets App Store CI</string>
    </dict>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
```

- [ ] **Step 4: archive.sh**

`ios/Scripts/archive.sh`:
```bash
#!/bin/bash
# Builds an App Store archive and exports the .ipa. Run from anywhere; paths are relative to ios/.
#
# Optional CI behaviour, all inert when the variables are unset (test-archive-args.sh proves it):
#   ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID  App Store Connect API key for a runner with no signed-in
#                                              Xcode account. All three or none.
#   BUILD_NUMBER          overrides CURRENT_PROJECT_VERSION for this build (applies to app and extension).
#   EXPORT_OPTIONS_PLIST  defaults to ExportOptions.plist (automatic, local). CI passes ExportOptions-ci.plist.
#   ARCHIVE_PRINT_ONLY=1  print the command lines and exit; used by the test.
#
# "${ARR[@]+"${ARR[@]}"}": macOS /bin/bash is 3.2, where `set -u` aborts on an empty array otherwise.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"

ASC_ARGS=()
if [ -n "${ASC_KEY_PATH:-}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    ASC_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
VERSION_ARGS=()
if [ -n "${BUILD_NUMBER:-}" ]; then
    VERSION_ARGS=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi
EXPORT_PLIST="${EXPORT_OPTIONS_PLIST:-ExportOptions.plist}"
ARCHIVE="$IOS/build/archive/Graphghan.xcarchive"
EXPORT_DIR="$IOS/build/archive/export"

# Defence against the one irreversible failure: with API-key auth and an automatic-signing plist, the
# export's -allowProvisioningUpdates would MINT a Distribution certificate. Refuse rather than trust the caller.
if [ -n "${ASC_KEY_PATH:-}" ] && [ -z "${EXPORT_OPTIONS_PLIST:-}" ]; then
    echo "error: ASC key auth requires an explicit manual-signing export plist." >&2
    echo "       set EXPORT_OPTIONS_PLIST (e.g. ExportOptions-ci.plist)." >&2
    exit 1
fi

if [ "${ARCHIVE_PRINT_ONLY:-}" = "1" ]; then
    echo "ARCHIVE: xcodebuild -project Graphghan.xcodeproj -scheme Graphghan -destination generic/platform=iOS" \
         "-configuration Release -archivePath $ARCHIVE" \
         "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" "${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"}" "archive"
    echo "EXPORT: xcodebuild -exportArchive -archivePath $ARCHIVE -exportOptionsPlist $EXPORT_PLIST" \
         "-exportPath $EXPORT_DIR" "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" "-allowProvisioningUpdates"
    exit 0
fi

cd "$IOS"
xcodegen generate --quiet
# No -allowProvisioningUpdates on the archive: CI signs manually with pre-installed profiles, and on
# an automatic-signing local run it would let xcodebuild mint a certificate when the identity is missing.
xcodebuild -project Graphghan.xcodeproj -scheme Graphghan \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath "$ARCHIVE" \
  "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" "${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"}" \
  archive
rm -rf "$EXPORT_DIR"
# /usr/bin first: a Homebrew rsync ahead on PATH breaks Xcode's IPA copy step ("Copy failed").
# -allowProvisioningUpdates is a no-op under the manual CI plist; locally it lets a first-time bundle
# id mint its App Store profile.
PATH="/usr/bin:$PATH" xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" -exportPath "$EXPORT_DIR" \
  "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" \
  -allowProvisioningUpdates
echo "IPA at $EXPORT_DIR/"
```
`chmod +x ios/Scripts/archive.sh`. Add `ios/build/` is already ignored; nothing new for `.gitignore` unless `ios/Scripts/.appstore.env` is introduced in Task 4 (it is: add `ios/Scripts/.appstore.env` to `.gitignore` now).

- [ ] **Step 5: Run the tests and a Debug build**

Run from `ios/`: `Scripts/test-archive-args.sh` (4 ok lines); `mise run script-test`; `mise run generate && mise run build` (the Debug simulator build must be unaffected by the Release-only signing changes). Also `xcodebuild -project Graphghan.xcodeproj -scheme Graphghan -configuration Release -destination 'generic/platform=iOS' -showBuildSettings | grep -E "CODE_SIGN_STYLE|PROVISIONING_PROFILE_SPECIFIER|CODE_SIGN_IDENTITY"` must show `Manual`, `Graphghan App Store CI`, `Apple Distribution` (and the same for `-target GraphghanWidgets` with the Widgets profile name).

- [ ] **Step 6: Commit**

```bash
git add ios/project.yml ios/ExportOptions.plist ios/ExportOptions-ci.plist ios/Scripts/archive.sh ios/Scripts/test-archive-args.sh .gitignore
git commit -m "build(ios): manual release signing, export options, and archive.sh with a print-only test"
```

---

### Task 4: Upload, JWT, and What-to-Test scripts

**Files:**
- Create: `ios/Scripts/asc-jwt.sh`, `ios/Scripts/test-asc-jwt.sh`, `ios/Scripts/upload.sh`, `ios/Scripts/whats-to-test.sh`, `ios/Scripts/test-whats-to-test.sh`, `ios/docs/whats-to-test.md` (empty file with a one-line HTML comment)

**Interfaces:**
- Produces: `asc-jwt.sh` prints a JWT from `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`; `asc-jwt.sh --der-to-jose` converts stdin. `upload.sh [--validate] [ipa]` with `ASC_KEY_ID`/`ASC_ISSUER_ID` (from env or `ios/Scripts/.appstore.env`) and optional `ASC_KEY_PATH`. `whats-to-test.sh --print | <build-number>`; tag prefix `ios-build-`; preamble file `ios/docs/whats-to-test.md`; bundle id `com.tylervick.graphghan`; env overrides `WHATS_TO_TEST_POLL_ATTEMPTS`, `WHATS_TO_TEST_POLL_DELAY`, `ASC_JWT`.

- [ ] **Step 1: asc-jwt.sh (verbatim from Waddle) and its test**

Copy `~/Documents/waddle/Scripts/asc-jwt.sh` to `ios/Scripts/asc-jwt.sh` unchanged except the header comment's `Scripts/test-asc-jwt.sh` references, which stay valid. `ios/Scripts/test-asc-jwt.sh`:
```bash
#!/bin/bash
# asc-jwt.sh: the DER->JOSE conversion must produce exactly 64 bytes (r||s, each left-padded to 32),
# including for a short r and for an r carrying DER's leading 0x00 sign byte. A wrong length is a
# bare 401 from App Store Connect with no diagnostic.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

jose_len() { # hex DER on stdin -> decoded byte length of the JOSE output
    python3 -c '
import sys, base64
s = sys.stdin.read().strip()
s += "=" * (-len(s) % 4)
print(len(base64.urlsafe_b64decode(s)))'
}
der() { python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))' "$1"; }

# r and s both 32 bytes, high bit clear.
R32=$(printf '1%.0s' $(seq 1 64)); S32=$(printf '2%.0s' $(seq 1 64))
out="$(der "30440220${R32}0220${S32}" | "$HERE/asc-jwt.sh" --der-to-jose)"
[ "$(jose_len <<<"$out")" -eq 64 ] || fail "plain 32/32 case: wrong length"
pass "32-byte r and s convert to 64 bytes"

# r has the high bit set, so DER prefixes 0x00 and encodes it as 33 bytes.
R_HI="ff$(printf '1%.0s' $(seq 1 62))"
out="$(der "3045022100${R_HI}0220${S32}" | "$HERE/asc-jwt.sh" --der-to-jose)"
[ "$(jose_len <<<"$out")" -eq 64 ] || fail "sign-byte case: wrong length"
pass "a DER sign byte is stripped"

# r is short (31 bytes) because DER drops leading zeros.
R_SHORT=$(printf '3%.0s' $(seq 1 62))
out="$(der "3043021f${R_SHORT}0220${S32}" | "$HERE/asc-jwt.sh" --der-to-jose)"
[ "$(jose_len <<<"$out")" -eq 64 ] || fail "short-r case: wrong length"
pass "a short r is left-padded"

# A real mint with a throwaway key produces three dot-separated parts and a 64-byte signature.
openssl ecparam -name prime256v1 -genkey -noout -out "$TMP/k.p8" 2>/dev/null
tok="$(ASC_KEY_ID=ABCDEFGHIJ ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH="$TMP/k.p8" "$HERE/asc-jwt.sh")"
[ "$(tr -cd '.' <<<"$tok" | wc -c | tr -d ' ')" -eq 2 ] || fail "token is not three parts"
[ "$(jose_len <<<"${tok##*.}")" -eq 64 ] || fail "minted signature is not 64 bytes"
pass "mints a three-part token with a 64-byte signature"
```

- [ ] **Step 2: upload.sh**

`ios/Scripts/upload.sh`:
```bash
#!/bin/bash
# Uploads (or with --validate, validates) the exported IPA to App Store Connect with an API key.
#   Scripts/upload.sh [--validate] [path-to-ipa]
# Needs ASC_KEY_ID and ASC_ISSUER_ID in the environment or in Scripts/.appstore.env (gitignored), and
# the .p8 either at ASC_KEY_PATH or where altool searches (~/.appstoreconnect/private_keys/AuthKey_<ID>.p8).
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"

ACTION="--upload-app"
if [ "${1:-}" = "--validate" ]; then ACTION="--validate-app"; shift; fi
IPA="${1:-$IOS/build/archive/export/Graphghan.ipa}"

# shellcheck disable=SC1091
[ -f "$IOS/Scripts/.appstore.env" ] && source "$IOS/Scripts/.appstore.env"
: "${ASC_KEY_ID:?set ASC_KEY_ID (env or Scripts/.appstore.env)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (env or Scripts/.appstore.env)}"
[ -f "$IPA" ] || { echo "IPA not found: $IPA (run Scripts/archive.sh first)" >&2; exit 1; }

KEY_ARGS=()
if [ -n "${ASC_KEY_PATH:-}" ]; then KEY_ARGS=(--p8-file-path "$ASC_KEY_PATH"); fi

echo "${ACTION#--} $IPA"
# Captured, not streamed: Xcode 26's altool has printed an ITMS error and still exited 0. Trusting the
# exit code alone would make a failed release look green.
set +e
OUT="$(xcrun altool "$ACTION" -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
        "${KEY_ARGS[@]+"${KEY_ARGS[@]}"}" 2>&1)"
RC=$?
set -e
printf '%s\n' "$OUT"
if [ "$RC" -ne 0 ]; then echo "error: altool exited $RC" >&2; exit "$RC"; fi
if grep -qE 'ERROR ITMS-|error:' <<<"$OUT"; then
    echo "error: altool reported an error but exited 0 (known Xcode 26 behaviour); treating as FAILED." >&2
    exit 1
fi
```

- [ ] **Step 3: The failing What-to-Test test**

`ios/Scripts/test-whats-to-test.sh` (hermetic: throwaway repos, no network):
```bash
#!/bin/bash
# Hermetic tests for whats-to-test.sh --print: every case builds a throwaway repo under $TMP.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# A repo with an ios-build-3 tag at the base commit, then $2 evaluated to add history.
make_repo() { # name, mutate-script
    d="$TMP/$1"; mkdir -p "$d/ios/Scripts" "$d/ios/docs"; cd "$d"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    git init -q .; git config user.email t@e.st; git config user.name T
    git config commit.gpgsign false; git config tag.gpgSign false
    cp "$HERE/whats-to-test.sh" ios/Scripts/whats-to-test.sh; chmod +x ios/Scripts/whats-to-test.sh
    : > ios/docs/whats-to-test.md
    git add -A; git commit -qm base
    git tag ios-build-3
    eval "$2"
    cd - >/dev/null
    echo "$d"
}
# A commit touching the given path with the given subject.
touch_commit() { # path, subject
    mkdir -p "$(dirname "$1")"; echo "$RANDOM" >> "$1"; git add -A; git commit -qm "$2"
}
notes() { (cd "$1" && ios/Scripts/whats-to-test.sh --print 2>&1); }

r="$(make_repo groups 'touch_commit ios/Graphghan/A.swift "feat(ios): bigger Done button (#12)"; touch_commit ios/Tests/T.swift "test(ios): cover the strip"; touch_commit patterns/x/pattern.toml "feat(patterns): add Standing Stones"; touch_commit graphghan/cli.py "fix(cli): typo"')"
out="$(notes "$r")" || fail "exited non-zero: $out"
grep -q "^Changes since build 3:" <<<"$out" || fail "heading missing; got: $out"
grep -q -- "- Bigger Done button$" <<<"$out" || fail "feat bullet missing or PR number kept; got: $out"
grep -q -- "- Add Standing Stones$" <<<"$out" || fail "patterns bullet missing; got: $out"
grep -q -- "- Cover the strip$" <<<"$out" || fail "behind-the-scenes bullet missing; got: $out"
! grep -q "typo" <<<"$out" || fail "a commit touching neither ios/ nor patterns/ must be omitted; got: $out"
[ "$(grep -n "^In the app" <<<"$out" | cut -d: -f1)" -lt "$(grep -n "^Behind the scenes" <<<"$out" | cut -d: -f1)" ] || fail "groups out of order"
pass "groups by conventional prefix, strips prefixes and PR numbers, omits unrelated commits"

r="$(make_repo preamble 'printf "Focus on the lock screen.\n" > ios/docs/whats-to-test.md; git add -A; git commit -qm p; touch_commit ios/x "fix(ios): thing"')"
out="$(notes "$r")"
grep -q "Focus on the lock screen." <<<"$out" || fail "preamble missing; got: $out"
[ "$(grep -n "Focus on" <<<"$out" | cut -d: -f1)" -lt "$(grep -n "since build 3" <<<"$out" | cut -d: -f1)" ] || fail "preamble not above the changelog"
pass "a preamble is included verbatim above the changelog"

r="$(make_repo nothing '')"
if notes "$r" >"$TMP/o" 2>&1; then fail "no changes and no preamble should fail"; fi
grep -qi "no changes" "$TMP/o" || fail "error did not explain; got: $(cat "$TMP/o")"
pass "fails when there is nothing to tell a tester"

r="$(make_repo bootstrap 'git tag -d ios-build-3 >/dev/null; touch_commit ios/x "feat(ios): first"')"
out="$(notes "$r")" || fail "bootstrap failed: $out"
grep -q "no previous build tag" <<<"$out" || fail "bootstrap heading missing; got: $out"
pass "with no tag the last 20 commits are used and the heading says so"

r="$(make_repo current 'touch_commit ios/x "feat(ios): one"; git tag ios-build-4; touch_commit ios/y "feat(ios): two"')"
out="$(cd "$r" && WHATS_TO_TEST_RANGE_ONLY=1 ios/Scripts/whats-to-test.sh 4 2>&1)" || fail "range-only run failed: $out"
grep -q "since build 3" <<<"$out" || fail "must anchor on the newest tag BELOW the current build; got: $out"
grep -q -- "- One$" <<<"$out" || fail "commit inside the range missing; got: $out"
! grep -q -- "- Two$" <<<"$out" || fail "commit after the current build's tag must not be listed; got: $out"
pass "a build number anchors on the newest tag below it"

r="$(make_repo trim "$(printf 'for i in $(seq 1 400); do touch_commit ios/f$i "feat(ios): change number $i with some padding text to make it long"; done')")"
out="$(notes "$r")" || fail "trim case failed"
[ "$(python3 -c 'import sys; print(len(sys.stdin.read()))' <<<"$out")" -le 3901 ] || fail "notes exceed the App Store Connect cap"
grep -q "more changes" <<<"$out" || fail "trimmed notes must say how many were dropped"
pass "over-long notes are trimmed on a bullet boundary with a count"
```

- [ ] **Step 4: Run to verify failure** → `chmod +x ios/Scripts/test-*.sh; ios/Scripts/test-whats-to-test.sh` fails: `whats-to-test.sh` missing.

- [ ] **Step 5: whats-to-test.sh**

`ios/Scripts/whats-to-test.sh` (the changelog is derived from git so it cannot go stale; the API half is Waddle's, minus PR lookups):
```bash
#!/bin/bash
# Assembles TestFlight "What to Test" notes and attaches them to a build in App Store Connect.
#   Scripts/whats-to-test.sh --print          assemble and print (no network)
#   Scripts/whats-to-test.sh <build-number>   assemble and attach via the App Store Connect API
#
# Notes = optional hand-written preamble (ios/docs/whats-to-test.md) + a changelog DERIVED from git:
# commits since the newest ios-build-* tag below the current build, restricted to paths a tester can
# notice (ios/ and patterns/), grouped "In the app" (feat/fix/perf) and "Behind the scenes" (the rest),
# with the conventional-commit prefix and any trailing "(#N)" removed. Trimmed to App Store Connect's
# whatsNew cap on a bullet boundary.
#
# WHATS_TO_TEST_RANGE_ONLY=1 with a build number prints the notes for that build and exits (test hook).
# WHATS_TO_TEST_POLL_ATTEMPTS / WHATS_TO_TEST_POLL_DELAY override the ingestion poll; ASC_JWT the JWT script.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$IOS/.." && pwd)"
cd "$ROOT"

PREAMBLE_FILE="ios/docs/whats-to-test.md"
API="https://api.appstoreconnect.apple.com"
BUNDLE_ID="com.tylervick.graphghan"
TAG_PREFIX="ios-build-"
POLL_ATTEMPTS="${WHATS_TO_TEST_POLL_ATTEMPTS:-30}"
POLL_DELAY="${WHATS_TO_TEST_POLL_DELAY:-30}"
ASC_JWT="${ASC_JWT:-$IOS/Scripts/asc-jwt.sh}"
NOTES_MAX=3900

# One bullet per commit in the range that touches ios/ or patterns/. Output lines: "<group>\t<text>".
changelog() { # git log range args...
    git log --format='%H%x09%s' "$@" -- ios patterns | while IFS=$'\t' read -r _sha subject; do
        [ -n "$subject" ] || continue
        prefix=""; text="$subject"
        case "$subject" in
            *:*) prefix="${subject%%:*}"; text="${subject#*: }" ;;
        esac
        # strip a trailing " (#123)"
        text="$(printf '%s' "$text" | sed -E 's/ \(#[0-9]+\)$//')"
        # capitalise the first character
        text="$(printf '%s' "$text" | python3 -c 'import sys; s=sys.stdin.read(); print(s[:1].upper()+s[1:], end="")')"
        kind="${prefix%%(*}"; kind="${kind%%!}"
        case "$kind" in
            feat|fix|perf) printf 'app\t%s\n' "$text" ;;
            *) printf 'other\t%s\n' "$text" ;;
        esac
    done
}

format_groups() { # reads changelog lines on stdin
    python3 -c '
import sys
app, other = [], []
for line in sys.stdin.read().splitlines():
    if "\t" not in line: continue
    kind, text = line.split("\t", 1)
    (app if kind == "app" else other).append("- " + text)
out = []
if app: out += ["In the app"] + app
if other:
    if out: out.append("")
    out += ["Behind the scenes"] + other
print("\n".join(out), end="")'
}

prev_tag() { # [current-build-number]
    printf '%s\n' "$TAG_LIST" | awk -v n="${1:-}" -v p="$TAG_PREFIX" '
        { num = $0; sub("^" p, "", num) }
        ($0 != "") && (n == "" || num + 0 < n + 0) { print; exit }'
}

assemble_notes() { # [current-build-number]
    PREAMBLE=""
    if [ -f "$PREAMBLE_FILE" ]; then
        # drop HTML comments, trailing whitespace, and leading blank lines
        PREAMBLE="$(sed -e 's/<!--.*-->//' -e 's/[[:space:]]*$//' "$PREAMBLE_FILE" | sed -e '/./,$!d')"
    fi
    TAG_ERR="$(mktemp "${TMPDIR:-/tmp}/wtt-tag.XXXXXX")"
    if ! TAG_LIST="$(git tag --list "${TAG_PREFIX}*" --sort=-v:refname 2>"$TAG_ERR")"; then
        echo "error: git tag --list failed; cannot determine the previous build tag." >&2
        cat "$TAG_ERR" >&2; rm -f "$TAG_ERR"; exit 1
    fi
    rm -f "$TAG_ERR"
    TAG="$(prev_tag "${1:-}")"
    if [ -n "$TAG" ]; then
        HEADING="Changes since build ${TAG#"$TAG_PREFIX"}:"
        if [ -n "${1:-}" ] && git rev-parse -q --verify "refs/tags/${TAG_PREFIX}$1" >/dev/null; then
            BODY="$(changelog "$TAG..${TAG_PREFIX}$1" | format_groups)"
        else
            BODY="$(changelog "$TAG..HEAD" | format_groups)"
        fi
    else
        HEADING="Recent changes (no previous build tag; showing the last 20 commits):"
        BODY="$(changelog --max-count=20 | format_groups)"
    fi
    if [ -z "$PREAMBLE" ] && [ -z "$BODY" ]; then
        echo "error: no changes since ${TAG:-the start of history} and $PREAMBLE_FILE is empty." >&2
        echo "       Nothing to tell a tester. Write a preamble or ship a build with changes in it." >&2
        exit 1
    fi
    OUT=""
    if [ -n "$PREAMBLE" ]; then OUT="$PREAMBLE"; [ -n "$BODY" ] && OUT="$OUT"$'\n\n'; fi
    if [ -n "$BODY" ]; then OUT="$OUT$HEADING"$'\n\n'"$BODY"; fi
    trim_notes "$OUT"
    printf '\n'
}

trim_notes() { # text
    TRIM_TEXT="$1" TRIM_MAX="$NOTES_MAX" python3 -c '
import os, sys
def emit(s): sys.stdout.buffer.write(s.encode("utf-8", "surrogateescape"))
text = os.environ["TRIM_TEXT"]; limit = int(os.environ["TRIM_MAX"])
if len(text) <= limit:
    emit(text); raise SystemExit(0)
def tail(n): return "\n… and %d more change%s" % (n, "" if n == 1 else "s")
lines = text.split("\n"); dropped = 0
while len(lines) > 1 and len("\n".join(lines)) + len(tail(dropped + 1)) > limit:
    if lines.pop().startswith("- "): dropped += 1
if dropped:
    while len(lines) > 1 and not lines[-1].startswith("- "): lines.pop()
out = "\n".join(lines) + (tail(dropped) if dropped else "")
emit(out[:limit])'
}

json_first() { # field-path e.g. "id" or "attributes.processingState"
    python3 -c '
import json, sys
doc = json.load(sys.stdin)
items = doc.get("data") or []
if not items: sys.exit(3)
cur = items[0]
for part in sys.argv[1].split("."):
    cur = (cur or {}).get(part)
print(cur if cur is not None else "")' "$1"
}
api_get() { curl -sS -f -H "Authorization: Bearer $TOKEN" "$API$1"; }
# Prints the field and returns 0; returns 3 on "no items"; 1 on a parse failure.
read_json_field() { # response, field-path
    local val rc
    if val="$(printf '%s' "$1" | json_first "$2" 2>/dev/null)"; then printf '%s' "$val"; return 0; else rc=$?; fi
    [ "$rc" -eq 3 ] && return 3
    return 1
}
api_send() { # method, path, json-body
    local resp
    if resp="$(curl -sS --fail-with-body -X "$1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            --data-binary @- "$API$2" <<< "$3")"; then return 0; fi
    printf '%s\n' "$resp" >&2
    return 1
}
loc_body() { # build-id, notes, [loc-id]
    LOC_BUILD_ID="$1" LOC_NOTES="$2" LOC_LOC_ID="${3:-}" python3 -c '
import json, os
data = {"type": "betaBuildLocalizations", "attributes": {"whatsNew": os.environ["LOC_NOTES"]}}
loc_id = os.environ.get("LOC_LOC_ID") or None
if loc_id: data["id"] = loc_id
else:
    data["attributes"]["locale"] = "en-US"
    data["relationships"] = {"build": {"data": {"type": "builds", "id": os.environ["LOC_BUILD_ID"]}}}
print(json.dumps({"data": data}))'
}

MODE="${1:---print}"
if [ "$MODE" = "--print" ]; then assemble_notes; exit 0; fi
BUILD="$MODE"
case "$BUILD" in ''|*[!0-9]*) echo "usage: $0 --print | <build-number>" >&2; exit 2 ;; esac
if [ "${WHATS_TO_TEST_RANGE_ONLY:-}" = "1" ]; then assemble_notes "$BUILD"; exit 0; fi

NOTES="$(assemble_notes "$BUILD")" || { echo "error: could not assemble notes for build $BUILD" >&2; exit 1; }
TOKEN="$("$ASC_JWT")" || { echo "error: could not mint an App Store Connect token" >&2; exit 1; }
if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::$TOKEN"; fi

APPS_RESP="$(api_get "/v1/apps?filter%5BbundleId%5D=$BUNDLE_ID")" || { echo "error: could not resolve the app id for $BUNDLE_ID" >&2; exit 1; }
if APP_ID="$(read_json_field "$APPS_RESP" id)"; then :; else
    rc=$?
    if [ "$rc" -eq 3 ]; then echo "error: App Store Connect has no app with bundle id $BUNDLE_ID (create the app record; see ios/docs/release.md)." >&2
    else echo "error: could not parse the apps response" >&2; fi
    exit 1
fi

# The build resource appears only once ingestion starts and sits in PROCESSING for minutes; poll for both.
STATE=""; BUILD_ID=""; attempt=0
while [ "$attempt" -lt "$POLL_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    RESP="$(api_get "/v1/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$BUILD")" || { echo "error: could not query builds" >&2; exit 1; }
    if BUILD_ID="$(read_json_field "$RESP" id)"; then :; else rc=$?; [ "$rc" -eq 3 ] || { echo "error: could not parse the builds response" >&2; exit 1; }; fi
    if STATE="$(read_json_field "$RESP" attributes.processingState)"; then :; else rc=$?; [ "$rc" -eq 3 ] || { echo "error: could not parse the builds response" >&2; exit 1; }; fi
    if [ -n "$BUILD_ID" ] && [ "$STATE" != "PROCESSING" ]; then break; fi
    if [ "$attempt" -lt "$POLL_ATTEMPTS" ]; then sleep "$POLL_DELAY"; fi
done
[ -n "$BUILD_ID" ] || { echo "error: build $BUILD never appeared in App Store Connect after $attempt attempts; notes not attached." >&2; exit 1; }
[ "$STATE" != "PROCESSING" ] || { echo "error: build $BUILD still PROCESSING after $POLL_ATTEMPTS attempts; notes not attached." >&2; exit 1; }

LOC_RESP="$(api_get "/v1/betaBuildLocalizations?filter%5Bbuild%5D=$BUILD_ID&filter%5Blocale%5D=en-US")" || { echo "error: could not look up localizations" >&2; exit 1; }
if LOC_ID="$(read_json_field "$LOC_RESP" id)"; then :; else rc=$?; [ "$rc" -eq 3 ] || { echo "error: could not parse the localizations response" >&2; exit 1; }; fi
BODY="$(loc_body "$BUILD_ID" "$NOTES" "$LOC_ID")"
if [ -n "$LOC_ID" ]; then
    api_send PATCH "/v1/betaBuildLocalizations/$LOC_ID" "$BODY" || { echo "error: failed to update the notes for build $BUILD" >&2; exit 1; }
else
    api_send POST "/v1/betaBuildLocalizations" "$BODY" || { echo "error: failed to create the notes for build $BUILD" >&2; exit 1; }
fi
echo "Attached What-to-Test notes to build $BUILD."
```
`ios/docs/whats-to-test.md`:
```markdown
<!-- Optional hand-written preamble for the next TestFlight build's What to Test notes. Leave empty to ship only the derived changelog. -->
```

- [ ] **Step 6: Run the script tests** → `cd ios && mise run script-test`: test-asc-jwt (4 ok), test-archive-args (4 ok), test-check-simulator (6 ok), test-whats-to-test (6 ok). Also `hk check --all` from the root (whitespace/newline hygiene on the new files).

- [ ] **Step 7: Commit**

```bash
git add ios/Scripts ios/docs/whats-to-test.md
git commit -m "build(ios): upload, JWT, and What-to-Test scripts with hermetic tests"
```

---

### Task 5: Profile helper and the TestFlight workflow

**Files:**
- Create: `ios/Scripts/asc-profiles.sh`, `.github/workflows/testflight.yml`

**Interfaces:**
- Consumes: Task 3's profile names and `archive.sh`; Task 4's `upload.sh`, `asc-jwt.sh`, `whats-to-test.sh`.
- Produces: `asc-profiles.sh` writes `ios/build/profiles/<name>.mobileprovision` for both profiles and prints the `gh secret set` commands the operator runs. Workflow `testflight.yml` with inputs `validate_only`, `build_number`; env `BUILD_NUMBER_OFFSET: 0`; tag `ios-build-N`; artifact `Graphghan-N-ipa`.

- [ ] **Step 1: asc-profiles.sh**

```bash
#!/bin/bash
# Creates (or re-downloads) the two manually managed App Store provisioning profiles through the App
# Store Connect API and writes them under ios/build/profiles/. Idempotent: an existing profile of the
# same name is downloaded, not recreated. Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (env or
# Scripts/.appstore.env). The App IDs must already exist with the App Group capability (Xcode's
# automatic signing created both on the first device build). Nothing here creates certificates: the
# profiles bind to the existing Apple Distribution certificate, the same one Waddle's p12 holds.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
[ -f "$IOS/Scripts/.appstore.env" ] && source "$IOS/Scripts/.appstore.env"
: "${ASC_KEY_ID:?}"; : "${ASC_ISSUER_ID:?}"; : "${ASC_KEY_PATH:?}"
API="https://api.appstoreconnect.apple.com"
OUT="$IOS/build/profiles"; mkdir -p "$OUT"
TOKEN="$("$IOS/Scripts/asc-jwt.sh")"
get() { curl -sS -f -H "Authorization: Bearer $TOKEN" "$API$1"; }
post() { curl -sS --fail-with-body -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @- "$API$1"; }
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

CERT_ID="$(get "/v1/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=10" \
  | jq_py 'items=[c for c in d["data"] if c["attributes"].get("certificateType")=="DISTRIBUTION"]; print(items[0]["id"] if items else "")')"
[ -n "$CERT_ID" ] || { echo "error: no Apple Distribution certificate on the account" >&2; exit 1; }

make_profile() { # bundle-id, profile-name, out-file
    local bid name file bundle_res existing
    bid="$1"; name="$2"; file="$3"
    bundle_res="$(get "/v1/bundleIds?filter%5Bidentifier%5D=$bid&limit=5" \
      | jq_py "items=[b for b in d['data'] if b['attributes']['identifier']=='$bid']; print(items[0]['id'] if items else '')")"
    [ -n "$bundle_res" ] || { echo "error: no App ID for $bid; build once for a device with automatic signing first" >&2; exit 1; }
    existing="$(get "/v1/profiles?filter%5Bname%5D=$(printf '%s' "$name" | sed 's/ /%20/g')&limit=5" \
      | jq_py "items=[p for p in d['data'] if p['attributes']['name']=='$name' and p['attributes'].get('profileState')=='ACTIVE']; print(items[0]['attributes']['profileContent'] if items else '')")"
    if [ -z "$existing" ]; then
        existing="$(printf '{"data":{"type":"profiles","attributes":{"name":"%s","profileType":"IOS_APP_STORE"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"%s"}},"certificates":{"data":[{"type":"certificates","id":"%s"}]}}}}' "$name" "$bundle_res" "$CERT_ID" \
          | post "/v1/profiles" | jq_py 'print(d["data"]["attributes"]["profileContent"])')"
        echo "created profile: $name"
    else
        echo "downloaded existing profile: $name"
    fi
    printf '%s' "$existing" | /usr/bin/base64 --decode > "$file"
    security cms -D -i "$file" | plutil -extract ExpirationDate raw - | sed "s/^/  expires: /"
}
make_profile com.tylervick.graphghan "Graphghan App Store CI" "$OUT/app.mobileprovision"
make_profile com.tylervick.graphghan.widgets "Graphghan Widgets App Store CI" "$OUT/widgets.mobileprovision"

cat <<EOM

Profiles written under $OUT. Set the repository secrets (never commit these files):
  gh secret set PROVISIONING_PROFILE_APP_BASE64     -R tylervick/graphghan < <(/usr/bin/base64 -i "$OUT/app.mobileprovision")
  gh secret set PROVISIONING_PROFILE_WIDGETS_BASE64 -R tylervick/graphghan < <(/usr/bin/base64 -i "$OUT/widgets.mobileprovision")
EOM
```
(`ios/build/` is git-ignored, so the downloaded profiles never enter the tree.) The implementer does NOT run this script against the real account; the operator does (Task 7's `release.md` says so). The implementer verifies it with `bash -n` and `shellcheck` if available.

- [ ] **Step 2: testflight.yml**

`.github/workflows/testflight.yml` (adapted from Waddle: dispatch only, no gate, two profiles, `ios-build-` tags, offset 0):
```yaml
name: TestFlight

# Manual only. Shipping is a deliberate act: no push, merge, or tag ships anything.
on:
  workflow_dispatch:
    inputs:
      validate_only:
        description: Validate the build without uploading (does not consume a build number)
        type: boolean
        required: false
        default: false
      build_number:
        description: Override the derived build number (use when retrying a release)
        type: string
        required: false
        default: ''

# Ref-independent so two dispatches on different refs serialize; no cancel, because cancelling
# mid-upload burns a build number server-side while reporting nothing.
concurrency:
  group: testflight
  cancel-in-progress: false

env:
  XCODE_VERSION: "26.2"
  # A new app: no build numbers are consumed, so the first CI release is 1. Numbers have gaps whenever
  # a run fails before the upload; App Store Connect needs unique and increasing, not contiguous.
  BUILD_NUMBER_OFFSET: 0

jobs:
  testflight:
    name: Archive and upload
    runs-on: macos-26
    timeout-minutes: 60
    # contents: write exists only for the ios-build-N tag push.
    permissions:
      contents: write
    steps:
      # Full history: whats-to-test.sh walks git log since the newest ios-build-* tag.
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          fetch-depth: 0

      # Fails in seconds instead of after a 20-minute archive.
      - name: Resolve and validate the build number
        id: buildnum
        env:
          OVERRIDE: ${{ inputs.build_number }}
          OFFSET: ${{ env.BUILD_NUMBER_OFFSET }}
          RUN_NUMBER: ${{ github.run_number }}
        run: |
          if [ -n "$OVERRIDE" ]; then N="$OVERRIDE"; else N=$(( OFFSET + RUN_NUMBER )); fi
          [[ "$N" =~ ^[0-9]+$ ]] || { echo "::error::build number '$N' is not numeric"; exit 1; }
          [ "$N" -ge 1 ] || { echo "::error::build number must be at least 1"; exit 1; }
          echo "value=$N" >> "$GITHUB_OUTPUT"
          echo "Build number: $N"

      - name: Select Xcode
        env:
          XCODE_VERSION: ${{ env.XCODE_VERSION }}
        run: |
          APP="/Applications/Xcode_${XCODE_VERSION}.app"
          [ -d "$APP" ] || { echo "::error::$APP not found on this runner image."; ls -d /Applications/Xcode*.app; exit 1; }
          sudo xcode-select -s "$APP"
          xcodebuild -version

      - uses: jdx/mise-action@c37c93293d6b742fc901e1406b8f764f6fb19dac # v2.4.4
        with: {cache: true, working_directory: ios}

      # No set -x anywhere here: a decoded .p8 is multi-line PEM and GitHub's masking needs a
      # single-line exact match, so it would NOT be redacted if it reached the log.
      - name: Install signing assets
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          PROVISIONING_PROFILE_APP_BASE64: ${{ secrets.PROVISIONING_PROFILE_APP_BASE64 }}
          PROVISIONING_PROFILE_WIDGETS_BASE64: ${{ secrets.PROVISIONING_PROFILE_WIDGETS_BASE64 }}
          ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
        run: |
          umask 077
          KC="$RUNNER_TEMP/build.keychain-db"
          KC_PW="$(uuidgen)"
          CERT="$RUNNER_TEMP/cert.p12"
          # Explicit /usr/bin/base64: bare `base64` is PATH-shadowable.
          printf '%s' "$BUILD_CERTIFICATE_BASE64" | /usr/bin/base64 --decode > "$CERT"
          printf '%s' "$PROVISIONING_PROFILE_APP_BASE64" | /usr/bin/base64 --decode > "$RUNNER_TEMP/app.mobileprovision"
          printf '%s' "$PROVISIONING_PROFILE_WIDGETS_BASE64" | /usr/bin/base64 --decode > "$RUNNER_TEMP/widgets.mobileprovision"
          printf '%s' "$ASC_PRIVATE_KEY" | /usr/bin/base64 --decode > "$RUNNER_TEMP/AuthKey_${ASC_KEY_ID}.p8"

          security create-keychain -p "$KC_PW" "$KC"
          security set-keychain-settings -lut 21600 "$KC"
          security unlock-keychain -p "$KC_PW" "$KC"
          security import "$CERT" -k "$KC" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
          # Append rather than replace: `-s` alone drops login.keychain.
          # shellcheck disable=SC2046
          security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
          # codesign: is REQUIRED; without it macOS queues a GUI prompt that never arrives headless and the job hangs.
          security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KC_PW" "$KC" >/dev/null

          # Both profile directories: Xcode 16+ reads the Developer/Xcode path, older tooling the MobileDevice one.
          UUIDS=""
          for P in "$RUNNER_TEMP/app.mobileprovision" "$RUNNER_TEMP/widgets.mobileprovision"; do
            UUID="$(security cms -D -i "$P" | plutil -extract UUID raw -)"
            for d in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
              mkdir -p "$d"; cp "$P" "$d/$UUID.mobileprovision"
            done
            UUIDS="$UUIDS $UUID"
          done
          echo "PROFILE_UUIDS=$UUIDS" >> "$GITHUB_ENV"

          # Scoped to $KC: the search-list-wide form would pass on ANY Distribution identity.
          if ! security find-identity -v -p codesigning "$KC" | grep -q 'Apple Distribution'; then
            echo "::error::No Apple Distribution identity in the ephemeral keychain (p12 missing its key, or expired)."
            security find-identity -v -p codesigning "$KC" || true
            exit 1
          fi
          security list-keychains -d user | grep -qF "$KC" || { echo "::error::$KC is not in the keychain search list."; exit 1; }

      - name: Archive and export
        env:
          ASC_KEY_PATH: ${{ runner.temp }}/AuthKey_${{ secrets.ASC_KEY_ID }}.p8
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          BUILD_NUMBER: ${{ steps.buildnum.outputs.value }}
          EXPORT_OPTIONS_PLIST: ExportOptions-ci.plist
        run: ios/Scripts/archive.sh

      # BEFORE the upload, so a failed upload does not discard the build.
      - name: Upload IPA artifact
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7
        with:
          name: Graphghan-${{ steps.buildnum.outputs.value }}-ipa
          path: ios/build/archive/export/*.ipa
          retention-days: 7

      - name: Upload to TestFlight
        env:
          ASC_KEY_PATH: ${{ runner.temp }}/AuthKey_${{ secrets.ASC_KEY_ID }}.p8
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          VALIDATE_ONLY: ${{ inputs.validate_only }}
        run: |
          if [ "$VALIDATE_ONLY" = "true" ]; then ios/Scripts/upload.sh --validate; else ios/Scripts/upload.sh; fi

      # Tag BEFORE attaching notes: the next release computes its changelog range from the tag.
      - name: Tag the shipped build
        if: ${{ inputs.validate_only != true }}
        env:
          N: ${{ steps.buildnum.outputs.value }}
        run: |
          if ! git tag "ios-build-$N" || ! git push origin "ios-build-$N"; then
            echo "::error::Build $N IS UPLOADED; only the ios-build-$N tag could not be recorded."
            echo "::error::Do not re-run (App Store Connect rejects a duplicate build). Tag by hand:"
            echo "::error::  git -c tag.gpgSign=false tag ios-build-$N && git push origin ios-build-$N"
            exit 1
          fi

      # Notes are metadata: a failure here does not mean the release failed, but it fails loudly
      # because a silent warning is how the field ends up empty.
      - name: Attach What to Test notes
        if: ${{ inputs.validate_only != true }}
        env:
          ASC_KEY_PATH: ${{ runner.temp }}/AuthKey_${{ secrets.ASC_KEY_ID }}.p8
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          N: ${{ steps.buildnum.outputs.value }}
        run: |
          if ! ios/Scripts/whats-to-test.sh "$N"; then
            echo "::error::Build $N IS UPLOADED; only the What-to-Test notes could not be attached."
            echo "::error::Re-running would upload again and consume another build number. Set the notes by hand in App Store Connect."
            exit 1
          fi

      # Raw xcodebuild writes these into TMPDIR. Artifact contents are not covered by secret masking
      # on a public repo, so the key id is scrubbed first.
      - name: Collect distribution logs
        if: failure()
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
        run: |
          mkdir -p "$RUNNER_TEMP/distlogs"
          cp -R "$TMPDIR"/*.xcdistributionlogs "$RUNNER_TEMP/distlogs/" 2>/dev/null || true
          if [ -n "${ASC_KEY_ID:-}" ]; then
            find "$RUNNER_TEMP/distlogs" -type f -print0 2>/dev/null | xargs -0 sed -i '' "s/${ASC_KEY_ID}/ASC_KEY_ID_REDACTED/g" 2>/dev/null || true
          fi
          ls -la "$RUNNER_TEMP/distlogs" || true
      - name: Upload distribution logs
        if: failure()
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7
        with:
          name: xcdistributionlogs
          path: ${{ runner.temp }}/distlogs
          retention-days: 3
          if-no-files-found: ignore

      - name: Summary
        if: always()
        env:
          REF: ${{ github.ref_name }}
          BUILD_NUM: ${{ steps.buildnum.outputs.value }}
          VALIDATE_ONLY: ${{ inputs.validate_only }}
        run: |
          if [ "$VALIDATE_ONLY" = "true" ]; then MODE="validate only"; else MODE="upload"; fi
          {
            echo "### TestFlight run"; echo
            echo "- Build number: **$BUILD_NUM**"; echo "- Mode: $MODE"; echo "- Ref: \`$REF\`"; echo
            echo "Confirm the build appears in App Store Connect: Xcode 26's altool can report success for an upload that did not happen."
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Delete keychain and signing material
        if: always()
        run: |
          security delete-keychain "$RUNNER_TEMP/build.keychain-db" 2>/dev/null || true
          rm -f "$RUNNER_TEMP"/AuthKey_*.p8 "$RUNNER_TEMP"/cert.p12 "$RUNNER_TEMP"/*.mobileprovision
          for u in ${PROFILE_UUIDS:-}; do
            rm -f "$HOME/Library/MobileDevice/Provisioning Profiles/$u.mobileprovision" \
                  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$u.mobileprovision"
          done
```
Note: `PROFILE_UUIDS` comes from `$GITHUB_ENV`, so it is read as a plain environment variable in the last step (no `${{ }}` needed). If zizmor flags the `sed -i ''` xargs line or anything else, fix per its message and record it.

- [ ] **Step 3: Lint and verify**

From the repo root: `hk check --all` (actionlint, zizmor), `mise run pin-actions`. From `ios/`: `bash -n Scripts/asc-profiles.sh`, `mise run script-test`. Expected: all clean.

- [ ] **Step 4: Commit**

```bash
git add ios/Scripts/asc-profiles.sh .github/workflows/testflight.yml
git commit -m "ci: manual TestFlight workflow with an ephemeral keychain, both profiles, and What-to-Test notes"
```

---

### Task 6: Release docs and README

**Files:**
- Create: `ios/docs/release.md`
- Modify: `ios/README.md`, `README.md`, `ios/docs/qa.md`

- [ ] **Step 1: release.md**

```markdown
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
   It creates or downloads "Graphghan App Store CI" and "Graphghan Widgets App Store CI" into `ios/build/profiles/` and prints the two `gh secret set` commands for `PROVISIONING_PROFILE_APP_BASE64` and `PROVISIONING_PROFILE_WIDGETS_BASE64`. The names must stay identical in `project.yml`, `ExportOptions-ci.plist`, and the portal. Profiles expire with the certificate; re-run the script after a renewal.
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
```

- [ ] **Step 2: README notes and qa.md**

In `ios/README.md` add a "CI and releases" section: the `ios` CI job (what it runs, that snapshots run in `render` mode there and land in the `ios-snapshots` artifact; `mise run ci-test` reproduces it; `GRAPHGHAN_SNAPSHOTS=record` re-records all references in one run), the `script-test` task, and a pointer to `docs/release.md`. In the root `README.md` "iOS app" paragraph add one sentence: "CI runs the iOS tests on every pull request that touches `ios/`, and `.github/workflows/testflight.yml` ships a build to TestFlight by hand (see `ios/docs/release.md`)." In `ios/docs/qa.md`, under "Live Activity", change the Dynamic Island line to: `- [ ] Dynamic Island: compact shows swatch + count and R<row>; long-press shows the expanded card with the title, row, swatch, colour name, next-run line, and the Back and Done buttons.` and add at the top: "Run this on a device build (`ios/README.md`) before dispatching the TestFlight workflow."

- [ ] **Step 3: Verify and commit**

Run from the root: `hk check --all` and `uv run pytest -q`; from `ios/`: `mise run core-test && mise run script-test && mise run test`.
```bash
git add ios/docs/release.md ios/README.md README.md ios/docs/qa.md
git commit -m "docs(ios): release runbook, CI notes, QA checklist update"
```

---

### Task 7: Finish the branch

- [ ] **Step 1: Push and open the PR**

Push `feat/ci-testflight` and open a pull request against `main` titled "iOS CI job and TestFlight workflow". Body: what the `ios` job runs, the snapshot render mode, the manual-signing release path, the scripts and their tests, and the operator steps that remain (secrets, profiles via `Scripts/asc-profiles.sh`, App Store Connect record and group). The PR itself is the proof of Task 2: wait for the `ios` job and report its result and duration in the PR description. If the job fails for a runner-image reason (Xcode path, simulator name or OS), fix the pin in `ci.yml` on the branch and push again; record what changed.

- [ ] **Step 2: After merge (operator, not the implementer)**

Set the seven secrets, run `Scripts/asc-profiles.sh`, create the app record and the TestFlight group, dispatch the workflow with `validate_only` first, then a real upload, then add the tester. Spec §11's first success criterion is checked on the tester's phone.

---

## Self-review notes

Spec coverage: §8.1 layout (ExportOptions plists, Scripts/, docs/qa.md and release.md), §8.2 identifiers (Global Constraints, plists, project.yml), §8.3 portal work (release.md steps 1–6; profiles scripted via the API, the rest by hand), §8.4 CI (Task 2: macos-26, path filter, mise, xcodegen, `swift test`, `xcodebuild test`, Xcode 26.2; the Python job already validates every fixture against the schema and runs the sequence conformance test in `tests/test_conformance.py` since Plan 1, so no change there), §8.5 TestFlight (Task 5: every listed element; secrets reused and new; nothing from the "not copied" list), §9 testing (script tests hermetic; snapshot strategy on a runner decided: render mode + artifact), §11 (release.md "Shipping a build").

Type/name consistency: profile names appear identically in Task 3 (`project.yml`, `ExportOptions-ci.plist`), Task 5 (`asc-profiles.sh`), Task 6 (`release.md`); tag prefix `ios-build-` in `whats-to-test.sh` (Task 4) and `testflight.yml` (Task 5); env keys `GRAPHGHAN_SNAPSHOTS` / `GRAPHGHAN_SNAPSHOT_OUT` in Task 1 (`Snapshots.swift`, `mise.toml`) and Task 2 (`ci.yml`, with the `TEST_RUNNER_` prefix); `archive.sh`'s env contract in Task 3's test and Task 5's workflow; artifact paths `ios/build/archive/export/*.ipa` in Task 3 and Task 5.

Known simplifications: `whats-to-test.sh` drops Waddle's pull-request summary lookups (this repo's commit subjects are already written as tester-readable sentences); the CI job has no iPad leg (iPhone-only app, `TARGETED_DEVICE_FAMILY: 1`); the `ios-changes` filter falls back to running the job when the diff range is unusable rather than skipping.

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

#!/bin/bash
# Hermetic tests for should-ship.sh: each case builds a throwaway repository with its own
# ios-build-* tags, so nothing here reads this repository's history or touches a network.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/should-ship.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# A repository shaped like this one: ios/ beside docs, with the script in place.
new_repo() {
    local dir="$TMP/$1"
    mkdir -p "$dir/ios/Scripts" "$dir/ios/docs" "$dir/ios/Tests" "$dir/ios/Graphghan"
    cp "$SCRIPT" "$dir/ios/Scripts/should-ship.sh"
    git -C "$dir" init -q
    git -C "$dir" config user.email t@example.test
    git -C "$dir" config user.name Test
    git -C "$dir" config commit.gpgSign false
    git -C "$dir" config tag.gpgSign false
    echo "$dir"
}

commit() {  # commit <dir> <path> <message>
    mkdir -p "$(dirname "$1/$2")"
    echo "$RANDOM" > "$1/$2"
    git -C "$1" add -A
    git -C "$1" commit -qm "$3"
}

ship() { (cd "$1" && ./ios/Scripts/should-ship.sh "${2:-HEAD}" 2>/dev/null); }

# --- no build has ever shipped ------------------------------------------------------------------

d="$(new_repo untagged)"
commit "$d" ios/Graphghan/App.swift "first"
[ "$(ship "$d")" = "true" ] || fail "an untagged repository should ship"
pass "with no ios-build-* tag at all, it ships"

# --- app code changed since the last build --------------------------------------------------------

d="$(new_repo changed)"
commit "$d" ios/Graphghan/App.swift "first"
git -C "$d" tag ios-build-1
commit "$d" ios/Graphghan/App.swift "second"
[ "$(ship "$d")" = "true" ] || fail "changed app code should ship"
pass "app code changed since the newest tag: ships"

# --- only docs, tests and scripts changed ---------------------------------------------------------

d="$(new_repo docsonly)"
commit "$d" ios/Graphghan/App.swift "first"
git -C "$d" tag ios-build-1
commit "$d" ios/docs/release.md "docs"
commit "$d" ios/Tests/AppTests.swift "tests"
commit "$d" ios/Scripts/helper.sh "scripts"
[ "$(ship "$d")" = "false" ] || fail "docs, tests and scripts alone should not ship"
pass "only docs, tests and scripts since the newest tag: does not ship"

# --- #193: the commit is an ancestor of what already shipped ---------------------------------------

d="$(new_repo ancestor)"
commit "$d" ios/Graphghan/App.swift "first"
EARLIER="$(git -C "$d" rev-parse HEAD)"
commit "$d" ios/Graphghan/Later.swift "second"
git -C "$d" tag ios-build-22  # the later commit shipped first, as in #193
[ "$(ship "$d" "$EARLIER")" = "false" ] || fail "a commit already contained in the newest build must not ship"
pass "a commit behind the newest build does not ship (#193)"

# The two-dot diff the gate used to run is what made that case look shippable: it reports the
# newer build's own files, in reverse. Pinned so nobody restores it thinking it equivalent.
two_dot="$(git -C "$d" diff --name-only "ios-build-22..$EARLIER" -- 'ios/' ':(exclude)ios/docs/' ':(exclude)ios/Tests/' ':(exclude)ios/Scripts/')"
[ -n "$two_dot" ] || fail "expected the two-dot diff to be non-empty, which was the bug"
pass "the two-dot diff really does report the newer build's files (the bug)"

# --- the tag itself ---------------------------------------------------------------------------

d="$(new_repo attag)"
commit "$d" ios/Graphghan/App.swift "first"
git -C "$d" tag ios-build-5
[ "$(ship "$d")" = "false" ] || fail "the shipped commit itself must not ship again"
pass "the commit the newest tag points at does not ship again"

# --- tags sort by number, not alphabetically ------------------------------------------------------

d="$(new_repo sorting)"
commit "$d" ios/Graphghan/App.swift "first"
git -C "$d" tag ios-build-9
commit "$d" ios/Graphghan/App.swift "second"
git -C "$d" tag ios-build-10
commit "$d" ios/docs/notes.md "docs only since build 10"
[ "$(ship "$d")" = "false" ] || fail "build 10 must count as newer than build 9"
pass "ios-build-10 is newer than ios-build-9, not older"

echo "all should-ship tests passed"

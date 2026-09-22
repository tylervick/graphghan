#!/bin/bash
# Whether this commit is worth a TestFlight build (#106, #193).
#   Scripts/should-ship.sh            answers for HEAD
#   Scripts/should-ship.sh <commit>   answers for that commit (the tests)
#
# Prints "true" or "false" on stdout and the reason on stderr. Two questions, in this order:
#
#   1. Is this commit already contained in the newest shipped build? Then there is nothing to ship,
#      whatever the diff says. This is the #193 case: two merges fourteen seconds apart, the later
#      one shipped first as build 22, and the earlier one -- an ancestor of it -- then asked
#      "what changed since build 22?", was shown build 22's own work in reverse by a two-dot diff,
#      and uploaded older code as build 23.
#   2. Has anything that goes into the binary changed since that build? Docs, tests and scripts do
#      not, so a push that only touches them is not worth a tester's download.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$IOS/.." && pwd)"
cd "$ROOT"

HEAD_REF="${1:-HEAD}"
TAG_PREFIX="ios-build-"

say() { echo "$1"; echo "$2" >&2; }

NEWEST="$(git tag --list "${TAG_PREFIX}*" --sort=-v:refname | head -n 1)"
if [ -z "$NEWEST" ]; then
    say true "No build shipped yet: shipping."
    exit 0
fi

# Contained in what already shipped -- an ancestor of it, or it exactly. Nothing to ship, and the
# diff below would be actively misleading, since it would show the newer build's own changes.
if git merge-base --is-ancestor "$HEAD_REF" "$NEWEST^{commit}" 2>/dev/null; then
    say false "$HEAD_REF is already contained in $NEWEST; not shipping (#193)."
    exit 0
fi

# Three dots: what this commit added since the two last had in common, never what the other side
# added. Two dots is what shipped the wrong build.
CHANGED="$(git diff --name-only "$NEWEST...$HEAD_REF" -- 'ios/' ':(exclude)ios/docs/' ':(exclude)ios/Tests/' ':(exclude)ios/Scripts/')"
if [ -n "$CHANGED" ]; then
    say true "App code changed since $NEWEST:"
    echo "$CHANGED" >&2
else
    say false "Nothing that goes into the binary has changed since $NEWEST; not shipping."
fi

#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Decides whether tonight's nightly runs, and works out its version, build number, tag and
# notes. Everything goes into $GITHUB_ENV for the later steps.
#
# A nightly's build number is the project's own with the date after it: 0.5.0 build 1 gives
# 1.20261124. TestFlight orders build numbers part by part, so that comes after release build
# 1 and before release build 2, and nightlies never take a number a release PR will need.
set -euo pipefail

out() { echo "$1=$2" >> "$GITHUB_ENV"; }
skip() { echo "$1"; out RUN false; exit 0; }

# The schedule fires at 23:00 and 00:00 UTC; only the one that's midnight in London runs.
if [ "${EVENT:-}" = schedule ] && [ "$(TZ=Europe/London date +%H)" != 00 ]; then
  skip "It isn't midnight in London; the other scheduled run takes tonight."
fi

head=$(git rev-parse HEAD)
last=$(git tag -l 'nightly-*' --sort=-creatordate | head -n 1)
if [ "${FORCE:-false}" != true ]; then
  if [ -n "$last" ] && [ "$(git rev-list -n 1 "$last")" = "$head" ]; then
    skip "Nothing new on main since $last."
  fi
  if git tag --points-at HEAD | grep -qE '^(iOS|macOS|tvOS)-[0-9]+\.[0-9]+\.[0-9]+-build-[0-9]+$'; then
    skip "main is a release build, already on TestFlight."
  fi
fi

settings=$(xcodebuild -scheme Arcfin -destination generic/platform=iOS -configuration Release -showBuildSettings 2>/dev/null)
setting() { awk -F' = ' -v key="$1" '$1 ~ "^ +" key "$" {print $2; exit}' <<< "$settings"; }
version=$(setting MARKETING_VERSION)
base=$(setting CURRENT_PROJECT_VERSION)
bundle=$(setting PRODUCT_BUNDLE_IDENTIFIER)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$base" =~ ^[0-9]+$ ]] || [ -z "$bundle" ]; then
  echo "::error::Couldn't read the version ($version), build ($base) or bundle ID ($bundle)"
  exit 1
fi

# A second run on the same day gets a third part: 1.20261124.2, tagged nightly-20261124-2.
date=$(TZ=Europe/London date +%Y%m%d)
build="$base.$date"
tag="nightly-$date"
n=1
while git rev-parse -q --verify "refs/tags/$tag" > /dev/null; do
  n=$((n + 1))
  build="$base.$date.$n"
  tag="nightly-$date-$n"
done

# What changed: since the last nightly, or for the first one since the last release.
since=$last
if [ -z "$since" ]; then
  since=$(git describe --tags --abbrev=0 --match '*-build-*' HEAD 2>/dev/null || true)
fi
notes="$RUNNER_TEMP/nightly-changes.txt"
git log --no-merges -n 60 --format='%s%x09%h' ${since:+"$since..HEAD"} > "$notes"

out RUN true
out VERSION "$version"
out BUILD "$build"
out BUNDLE_ID "$bundle"
out NIGHTLY_TAG "$tag"
out PREVIOUS_TAG "$since"
out CHANGES "$notes"
echo "Nightly $version ($build) from $(git rev-parse --short HEAD), tagged $tag, $(wc -l < "$notes" | tr -d ' ') change(s) since ${since:-the start}"

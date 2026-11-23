#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Decides whether tonight's nightly runs, and works out its version, build number, tag and
# notes. Everything goes into $GITHUB_ENV for the later steps.
#
# A nightly's build number is the project's own with the Unix time after it: 0.5.0 build 2
# built at 1764028800 gives 2.1764028800. TestFlight orders build numbers part by part, so that
# comes after release build 2 and before release build 3, nightlies never take a number a
# release PR will need, and a second build the same day (a hotfix) still gets a new one.
set -euo pipefail

out() { echo "$1=$2" >> "$GITHUB_ENV"; }
skip() { echo "$1"; out RUN false; exit 0; }

# The schedule fires at 23:00 and 00:00 UTC; only the one that's midnight in Dublin runs.
if [ "${EVENT:-}" = schedule ] && [ "$(TZ=Europe/Dublin date +%H)" != 00 ]; then
  skip "It isn't midnight in Dublin; the other scheduled run takes tonight."
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

now=$(date +%s)
build="$base.$now"
tag="nightly-$(TZ=Europe/Dublin date -r "$now" +%Y%m%d)-$now"

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

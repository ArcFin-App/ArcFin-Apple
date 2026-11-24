#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Decides whether tonight's run builds, and works out its version, build number and tag. They
# go into $GITHUB_OUTPUT for the later jobs.
#
# It builds when main has commits since the last build's tag (or when forced). The build
# number is the project's with the Unix time after it: build 2 built at 1764028800 is
# 2.1764028800. TestFlight orders build numbers part by part, so the builds of 2 come after 1
# and before 3, in the order they were made, nothing is committed, and a second run the same
# day (a hotfix, or a run repeated after a failure) still gets a number Apple hasn't seen.
# The tag is v<version>-build-<build number>, e.g. v0.5.0-build-2.1764028800.
set -euo pipefail

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
skip() { echo "$1"; out run false; exit 0; }

# The schedule fires at 23:00 and 00:00 UTC; only the one that's midnight in Dublin runs.
if [ "${EVENT:-}" = schedule ] && [ "$(TZ=Europe/Dublin date +%H)" != 00 ]; then
  skip "It isn't midnight in Dublin; the other scheduled run takes tonight."
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

head=$(git rev-parse HEAD)
# The last build this commit builds on: this scheme's tags, and the older per-platform ones.
last=$(git describe --tags --abbrev=0 --match 'v*-build-*' --match 'nightly-*' --match '*-build-*' HEAD 2>/dev/null || true)
if [ "${FORCE:-false}" != true ] && [ -n "$last" ] && [ "$(git rev-list -n 1 "$last")" = "$head" ]; then
  skip "Nothing new on main since $last."
fi

build="$base.$(date +%s)"
out run true
out version "$version"
out build "$build"
out bundle "$bundle"
out tag "v$version-build-$build"
out previous "$last"
out sha "$head"
echo "$version ($build) from $(git rev-parse --short HEAD), $(git rev-list --count --no-merges ${last:+"$last.."}HEAD) change(s) since ${last:-the start}"

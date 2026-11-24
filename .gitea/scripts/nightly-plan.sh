#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Decides what tonight's run does, and works out its version, build number, tags and notes.
# Everything goes into $GITHUB_ENV for the later steps.
#
# - Release: the project's version and build has no <Platform>-X.Y.Z-build-N tag yet, so a
#   version or build bump has reached main. It uploads and tags it as build N. A platform that
#   didn't make it is tried again the next night.
# - Nightly: main has commits since the last nightly or release.
#
# Either way the number uploaded is the project's build with the Unix time after it: build 2
# built at 1764028800 is 2.1764028800. TestFlight orders build numbers part by part, so builds
# of N stay after N-1 and before N+1, in the order they were made, and a second run the same
# day (a hotfix, or a release run repeated after a failure) still gets a new number.
set -euo pipefail

out() { echo "$1=$2" >> "$GITHUB_ENV"; }
skip() { echo "$1"; out RUN false; exit 0; }

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

untagged=()
for platform in iOS macOS tvOS; do
  git rev-parse -q --verify "refs/tags/$platform-$version-build-$base" > /dev/null || untagged+=("$platform")
done

head=$(git rev-parse HEAD)
# The last nightly or release this commit builds on.
last=$(git describe --tags --abbrev=0 --match 'nightly-*' --match '*-build-*' HEAD 2>/dev/null || true)

now=$(date +%s)
build="$base.$now"
if [ ${#untagged[@]} -gt 0 ]; then
  mode=release
  platforms="${untagged[*]}"
  tag=""
  since=$(git describe --tags --abbrev=0 --match '*-build-*' --exclude "*-$version-build-$base" HEAD 2>/dev/null || true)
else
  if [ "${FORCE:-false}" != true ] && [ -n "$last" ] && [ "$(git rev-list -n 1 "$last")" = "$head" ]; then
    skip "Nothing new on main since $last."
  fi
  mode=nightly
  platforms="iOS macOS tvOS"
  tag="nightly-$(TZ=Europe/Dublin date -r "$now" +%Y%m%d)-$now"
  since=$last
fi

notes="$RUNNER_TEMP/nightly-changes.txt"
git log --no-merges -n 60 --format='%s%x09%h' ${since:+"$since..HEAD"} > "$notes"

out RUN true
out MODE "$mode"
out VERSION "$version"
out BUILD "$build"
out BASE_BUILD "$base"
out PLATFORMS "$platforms"
out BUNDLE_ID "$bundle"
out NIGHTLY_TAG "$tag"
out PREVIOUS_TAG "$since"
out CHANGES "$notes"
echo "$mode: $version ($build) for $platforms from $(git rev-parse --short HEAD), $(wc -l < "$notes" | tr -d ' ') change(s) since ${since:-the start}"

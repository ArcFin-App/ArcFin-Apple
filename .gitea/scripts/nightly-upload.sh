#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Archives and uploads each platform with the nightly's build number. One platform failing
# doesn't stop the others; UPLOADED lists the ones that made it.
set -uo pipefail

cat > "$RUNNER_TEMP/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

auth=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
uploaded=()
for platform in ${PLATFORMS:-iOS macOS tvOS}; do
  echo "== $platform $VERSION ($BUILD)"
  # Uploaded by an earlier run that stopped before tagging: Apple won't take the number again.
  if [ "${MODE:-}" = release ] && EXISTS_FOR=$platform python3 -I .gitea/scripts/testflight-nightly.py; then
    echo "$platform $VERSION ($BUILD) is already on App Store Connect"
    uploaded+=("$platform")
    continue
  fi
  archive="$RUNNER_TEMP/Arcfin-$platform.xcarchive"
  log="$RUNNER_TEMP/archive-$platform.log"
  if ! xcodebuild -scheme Arcfin -configuration Release -destination "generic/platform=$platform" \
      -archivePath "$archive" -derivedDataPath "$RUNNER_TEMP/dd-$platform" \
      -disableAutomaticPackageResolution -skipMacroValidation -skipPackagePluginValidation \
      "${auth[@]}" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CURRENT_PROJECT_VERSION="$BUILD" \
      archive > "$log" 2>&1; then
    echo "::error::$platform didn't archive"
    grep ' error:' "$log" | sort -u | head -n 20
    tail -n 40 "$log"
    continue
  fi
  log="$RUNNER_TEMP/export-$platform.log"
  if ! xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" \
      -exportPath "$RUNNER_TEMP/export-$platform" "${auth[@]}" > "$log" 2>&1; then
    echo "::error::$platform didn't upload"
    grep -iE 'error' "$log" | sort -u | head -n 20
    continue
  fi
  echo "$platform uploaded"
  uploaded+=("$platform")
  rm -rf "$RUNNER_TEMP/dd-$platform" "$archive"
done

echo "UPLOADED=${uploaded[*]:-}" >> "$GITHUB_ENV"
[ ${#uploaded[@]} -gt 0 ] || { echo "::error::Nothing uploaded"; exit 1; }

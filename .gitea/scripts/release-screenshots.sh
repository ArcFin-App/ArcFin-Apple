#!/usr/bin/env bash
# Runs ScreenshotTests for one platform and zips its screenshots as WebP.
#
# usage: release-screenshots.sh <iOS|macOS|tvOS> <output.zip>
#
# iOS covers the largest iPhone and iPad simulators, tvOS an Apple TV 4K simulator, each on
# the newest runtime installed. macOS runs on this Mac's logged-in session and drives it for
# a few minutes; the test runner needs Accessibility permission there.
set -euo pipefail

platform=$1
out=$2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The newest-runtime device whose name matches each pattern in turn; prints its UDID.
pick_simulator() {
  xcrun simctl list devices available -j | python3 -I -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return tuple(int(n) for n in re.findall(r"\d+", runtime.rsplit(".", 1)[-1]))
for pattern in sys.argv[1:]:
    found = [(version(rt), d["udid"]) for rt, ds in devices.items() for d in ds if re.search(pattern, d["name"])]
    if found:
        print(max(found)[1])
        break
' "$@"
}

capture() {
  local name=$1 destination=$2 udid=${3:-}
  if [ -n "$udid" ]; then
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl ui "$udid" appearance dark 2>/dev/null || true
    xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
      --cellularBars 4 --wifiBars 3 2>/dev/null || true
  fi
  echo "Capturing $name"
  # A screen that can't be reached fails its own test; the rest still count.
  xcodebuild test \
    -scheme Arcfin \
    -destination "$destination" \
    -derivedDataPath "$work/dd" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -parallel-testing-enabled NO \
    -only-testing:ArcfinUITests/ScreenshotTests \
    -resultBundlePath "$work/$name.xcresult" \
    > "$work/$name.log" 2>&1 || grep -E "Test [Cc]ase.*failed" "$work/$name.log" || true
  [ -n "$udid" ] && xcrun simctl shutdown "$udid" 2>/dev/null || true
  [ -d "$work/$name.xcresult" ] || return 0
  mkdir -p "$work/attachments/$name" "$work/shots"
  xcrun xcresulttool export attachments --path "$work/$name.xcresult" --output-path "$work/attachments/$name" >/dev/null
  # Only the screenshots, named <Device>-<NN>-<screen>.png.
  python3 -I - "$work/attachments/$name" "$work/shots" <<'PY'
import json, os, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(source, "manifest.json"))):
    for attachment in test["attachments"]:
        match = re.match(r"((?:iPhone|iPad|Mac|AppleTV)-\d\d-[a-z-]+)", attachment.get("suggestedHumanReadableName", ""))
        if match:
            shutil.copy(os.path.join(source, attachment["exportedFileName"]), os.path.join(target, match[1] + ".png"))
PY
}

case "$platform" in
  iOS)
    iphone=$(pick_simulator 'iPhone \d+ Pro Max')
    capture iPhone "id=$iphone" "$iphone"
    ipad=$(pick_simulator 'iPad Pro.*13' '13-inch' 'iPad Pro')
    capture iPad "id=$ipad" "$ipad"
    ;;
  tvOS)
    tv=$(pick_simulator '^Apple TV 4K \(\w+ generation\)$' 'Apple TV 4K')
    capture AppleTV "id=$tv" "$tv"
    ;;
  macOS)
    capture Mac "platform=macOS"
    ;;
  *)
    echo "Unknown platform $platform" >&2
    exit 1
    ;;
esac

shots=("$work"/shots/*.png)
if [ ! -e "${shots[0]}" ]; then
  echo "No screenshots were captured"
  exit 1
fi

# The website's sizes (arcfin-site README): 660 px wide in portrait, 1400 px in landscape.
cwebp=$(command -v cwebp || echo /opt/homebrew/bin/cwebp)
for png in "${shots[@]}"; do
  [ -x "$cwebp" ] || break
  width=$(sips -g pixelWidth "$png" | awk '/pixelWidth/ {print $2}')
  height=$(sips -g pixelHeight "$png" | awk '/pixelHeight/ {print $2}')
  target=1400
  [ "$height" -gt "$width" ] && target=660
  "$cwebp" -quiet -q 85 -resize "$target" 0 "$png" -o "${png%.png}.webp" && rm "$png"
done

rm -f "$out"
(cd "$work/shots" && zip -q "$out" ./*)
echo "Packed $(ls "$work/shots" | wc -l | tr -d ' ') screenshots into $out"

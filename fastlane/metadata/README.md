# App Store Connect / TestFlight metadata

This folder isn't wired up to run via `fastlane` — it's the standard `fastlane deliver`
folder layout used as a plain reference, so this content lives in git next to the app
instead of only existing inside App Store Connect's web form. Copy each file's contents
into the matching App Store Connect field.

- `metadata/en-GB/*.txt` — App Store listing fields (App Information / Version Information)
- `metadata/en-GB/review_information/*.txt` — App Review Information tab (sign-in demo account + notes)
- `metadata/testflight/*.txt` — TestFlight's Test Information tab (not a real `deliver` path, just grouped here for the same copy-paste purpose)
- `metadata/copyright.txt` — App Information > copyright line

The locale is `en-GB` (English, UK), not `en-US` — set **App Store Connect > App Information
> Primary Language** to "English (UK)" to match. All copy here is written in British
English (colour, favourites, etc.) — keep it that way in any future edits.

**Before submitting**, see the caveat in `en-GB/review_information/notes.txt` — the demo
Jellyfin server sign-in there was updated to match how the public demo account actually
works (username only, no password — see the note there for why).

## App Information (not file-backed — set directly in App Store Connect)

- **Primary language:** English (UK)
- **Primary category:** Entertainment
- **Secondary category:** none needed, or Utilities if you want a second one listed
- **Age rating:** recommend **17+**. Arcfin plays whatever's on the Jellyfin server it's
  pointed at — that's entirely the user's own, unmoderated library, which Apple's age
  rating questionnaire treats the same way as unrestricted web/user-generated content.
  This is also how comparable third-party Jellyfin/Plex clients are typically rated.
  Walk through the actual questionnaire yourself since Apple's wording/options change,
  but expect to answer "yes" to the unrestricted/user-generated content question.
- **Price:** free (no in-app purchases exist in the app currently)

## App Privacy ("Nutrition Label") questionnaire

**Do you or your third-party partners collect data? Yes** — not because Arcfin's own code
phones home anywhere (see `Telemetry`, which is local `OSLog` only, no analytics SDK), but
because two embedded third-party SDKs are responsible for their own data practices, and
Apple's questionnaire explicitly covers "third-party partners... whose code you have added
to the app":

| Data type | Purpose | Linked to identity | Used for tracking | Source |
|---|---|---|---|---|
| **Device ID** | App Functionality + Analytics | No | No | Google Cast SDK (confirmed via its own embedded manifest — see below) |
| **Product Interaction** | App Functionality + Analytics | No | No | Google Cast SDK |
| **Other Diagnostic Data** | App Functionality + Analytics | No | No | Google Cast SDK |

Confirmed straight from Xcode's own Privacy Report for the archive (Organizer > archive >
"..." > Generate Privacy Report — a copy is saved in `metadata/privacy-reports/`), which
reads `GoogleCast.framework`'s actual embedded `PrivacyInfo.xcprivacy` manifest. This is a
more authoritative source than Google's own Cast SDK support-page prose, which additionally
claims Coarse Location and "Performance Data" apply — the real, shipped manifest doesn't
declare Location at all, and uses "Other Diagnostic Data" rather than "Performance Data."
Trust the manifest (it's what's actually in the binary and what Apple's own tooling reads),
not the support page. If you ever bump the Cast SDK version, re-run Generate Privacy Report
and diff it against this table.

Open question, your call: whether **Third-Party Advertising** should also apply to Device
ID / Product Interaction because of YouTube's embedded trailer player (SvenTiigi/
YouTubePlayerKit) — trailers can carry pre-roll ads the video's own uploader enabled, which
Arcfin has no control over or visibility into. Not something I can verify with certainty
from the code, so it's a risk-tolerance call, not a correctness one.

Everything else — Contact Info, Health, Financial, **Location** (the Wi-Fi-name permission
never reads an actual coordinate — see Info.plist notes below), User Content, Browsing/
Search History, User ID, Purchases, Crash Data, Surroundings, Body — **No**, not collected.

**Tracking:** answer "No, we do not track users" for the app as a whole — nothing here
links data across other companies' apps/sites for ad targeting from Arcfin's own side.

## Permission usage strings actually in the app (Info.plist)

- `NSFaceIDUsageDescription` — App Lock (Face ID)
- `NSLocalNetworkUsageDescription` — Jellyfin server / Chromecast discovery on the local network
- `NSLocationWhenInUseUsageDescription` — reading the current Wi-Fi name for home/away server switching (see the Location row above — permission requested, but no location data collected)

If Apple's review team asks why location permission is requested for an app that
"doesn't need a map," the answer is exactly the `NSLocationWhenInUseUsageDescription`
string above — point them at Settings > Server's Wi-Fi-based address switching.

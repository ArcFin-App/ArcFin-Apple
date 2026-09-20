# App Store Connect / TestFlight metadata

This folder isn't wired up to run via `fastlane` — it's the standard `fastlane deliver`
folder layout used as a plain reference, so this content lives in git next to the app
instead of only existing inside App Store Connect's web form. Copy each file's contents
into the matching App Store Connect field.

- `metadata/en-US/*.txt` — App Store listing fields (App Information / Version Information)
- `metadata/en-US/review_information/*.txt` — App Review Information tab (sign-in demo account + notes)
- `metadata/testflight/*.txt` — TestFlight's Test Information tab (not a real `deliver` path, just grouped here for the same copy-paste purpose)
- `metadata/copyright.txt` — App Information > copyright line

**Before submitting**, see the caveat in `en-US/review_information/notes.txt` — the demo
Jellyfin server credentials there (`demo`/`demo`) were not verified live and should be
checked, or swapped for a real test account, before you submit for review.

## App Information (not file-backed — set directly in App Store Connect)

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

Based on an audit of what the app actually does (not aspirational — see `CLAUDE.md`'s
CloudKit-sync line, which isn't implemented yet, so isn't answered here):

| Data type | Collected? | Notes |
|---|---|---|
| Contact Info, Health, Financial, Browsing History, Search History, Identifiers, Purchases | **No** | None of these are gathered anywhere in the app. |
| **Location** | **No** | Arcfin requests When-In-Use location permission, but only as an OS-level gate `NEHotspotNetwork.fetchCurrent` requires to read the *current Wi-Fi network name* (for switching between a server's local/remote address at home vs. away). It never calls `startUpdatingLocation()` or reads a coordinate — no location data is ever actually collected, stored, or transmitted. Answer "No" here; don't let the permission prompt's existence make you answer "Yes." |
| **User Content** (e.g. photos/videos) | **No, not collected by us** | Downloaded media and any credentials/library data live only on-device and on the user's own server — nothing is sent to us, because there's no "us" server in the data path. |
| **Diagnostics** (crash data) | Depends on whether the user opts into sharing crash reports with Apple | Arcfin itself has no crash reporting or analytics SDK (see `Telemetry` package — it's local `OSLog` only). If you don't add Apple's own opt-in crash reporting toggle, answer "No" across the board. |
| **Usage Data / Analytics** | **No** | No analytics SDK of any kind is integrated. |

**Tracking:** answer "No, we do not track users" — there's no advertising SDK, no
cross-app/cross-site tracking, no IDFA usage.

## Permission usage strings actually in the app (Info.plist)

- `NSFaceIDUsageDescription` — App Lock (Face ID)
- `NSLocalNetworkUsageDescription` — Jellyfin server / Chromecast discovery on the local network
- `NSLocationWhenInUseUsageDescription` — reading the current Wi-Fi name for home/away server switching (see the Location row above — permission requested, but no location data collected)

If Apple's review team asks why location permission is requested for an app that
"doesn't need a map," the answer is exactly the `NSLocationWhenInUseUsageDescription`
string above — point them at Settings > Server's Wi-Fi-based address switching.

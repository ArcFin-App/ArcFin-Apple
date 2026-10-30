# Contributing to Arcfin

Thanks for helping. Arcfin is maintained by one person, so replies can take a few days, but issues and pull requests from anyone are welcome.

- [Ways to help](#ways-to-help)
- [Before you start](#before-you-start)
- [Building Arcfin](#building-arcfin)
- [Conventions](#conventions)
- [Branches](#branches)
- [Pull requests](#pull-requests)
- [AI-assisted contributions](#ai-assisted-contributions)
- [Translating Arcfin](#translating-arcfin)
- [Reporting bugs](#reporting-bugs)
- [License and the DCO](#license-and-the-dco)

## Ways to help

- **Report a bug or suggest a feature** with the [issue templates](https://git.psmattas.com/ArcFin/ArcFin/issues/new/choose).
- **Test the beta** on [TestFlight](https://testflight.apple.com/join/kkC58n2w) and report what breaks.
- **Translate**, or check one of the machine-made translations. See [Translating Arcfin](#translating-arcfin).
- **Fix or build something.** New here? Start with [Start here: good first issues](https://git.psmattas.com/ArcFin/ArcFin/issues/255), pinned at the top of the issue list. It links every open issue labelled [`Good First Issue`](https://git.psmattas.com/ArcFin/ArcFin/issues?state=open&labels=1253): small, already agreed, and saying where to start. After that, any issue labelled `Reviewed/Confirmed` with a priority is open for work.
- **Improve the docs.** Typos and unclear wording count.

## Before you start

For anything bigger than a small fix, **open an issue first** and say what you'd like to do. It avoids two people working on the same thing, and gives a chance to agree on the approach before you write the code. New screens need an agreed design before work starts.

## Building Arcfin

**You'll need:**
- a Mac with **Xcode 26** or later;
- the iOS 26, macOS 26 and tvOS 26 SDKs that come with it.

**To build and run:**
1. Clone the repository and open `Arcfin.xcodeproj`.
2. Choose the **Arcfin** scheme and an iPhone, iPad, Mac or Apple TV destination.
3. To run on a device, set your own team and bundle identifier under **Signing & Capabilities**.

The packages in `LocalPackages/` are already part of the project, and dependencies resolve on the first build. Package versions are pinned in the committed `Package.resolved` files. Don't update them in an unrelated pull request.

**To run the package tests:**

```sh
cd LocalPackages && swift test --force-resolved-versions
```

Before opening a pull request, build for **all three platforms**, iOS, macOS and tvOS, since most code is shared. CI does the same.

How the code is organised is described in [ARCHITECTURE.md](ARCHITECTURE.md).

## Conventions

- **Swift 6 with strict concurrency.** Code must build without new warnings.
- **SwiftUI** for the interface. Use UIKit or AppKit only where a system API needs it.
- **State** in plain `@Observable` classes with `@State` and `@Environment`, not TCA.
- **Comments** only to explain a *why* that isn't obvious from the code. No docstrings that repeat the code.
- **Tests** use Swift Testing, not XCTest. Logic changes should come with tests.
- **User-facing text** must be translatable: pass `LocalizedStringKey` or `String(localized:)` to views, never a plain `String`. New text belongs in the String Catalogs in the same pull request. Building in Xcode adds it for you, and CI fails if anything is missing.
- **Design:** follow Apple's Human Interface Guidelines, using the colours and type in `DT` ([ARCHITECTURE.md](ARCHITECTURE.md#design-system)).
- **Networking:** a new HTTP client needs `waitsForConnectivity` and the network-path wait ([ARCHITECTURE.md](ARCHITECTURE.md#networking)).
- **Keep changes focused.** Avoid refactoring code your change doesn't need.

## Where platform code goes

Each screen is moving to its own view per platform over shared logic ([#198](https://git.psmattas.com/ArcFin/ArcFin/issues/198)), so a change for one platform can't break another. Xcode compiles each platform folder only for that platform, so files there need no `#if os(...)`:

| Folder | Builds for | Holds |
|---|---|---|
| `Arcfin/Shared/` | Every platform | Per-screen state (`@Observable`), loading, sorting, filtering and playback decisions, and views that look the same everywhere |
| `Arcfin/iOS/` | iPhone and iPad | iPhone screens, and the iPad ones until an iPad layout needs its own view |
| `Arcfin/iPadOS/` | iPhone and iPad | iPad screens whose layout differs from iPhone |
| `Arcfin/macOS/` | Mac | Mac screens |
| `Arcfin/tvOS/` | Apple TV | Apple TV screens |

- Inside each folder, one subfolder per screen: `Shared/Home/`, `iOS/Home/`, `tvOS/Home/` and so on.
- **Each platform names the screen the same**: `iOS/Search/SearchView.swift`, `macOS/Search/SearchView.swift` and `tvOS/Search/SearchView.swift` all define `SearchView`. Only one of them builds for each platform, so code that opens Search writes `SearchView(...)` and gets that platform's screen with no `#if`.
- **No `#if os(...)` in a platform folder.** CI fails if one appears. If two platforms need the same code, it belongs in `Shared/`.
- **Small differences inside a shared view** (pointer hover, focus) go through a modifier that each platform defines under the same name in its `Platform/` folder. For example, `onPointerHover` in `iOS/Platform/PointerHover.swift` uses `onHover`, and the tvOS one does nothing. The shared view calls it without `#if`.
- **Logic goes in `Shared/`.** A platform view lays the screen out and calls the shared state; it doesn't load, filter or decide anything itself.
- **iPad** isn't a separate platform to the compiler: `#if os(iOS)` is true on iPad and it's one app. The iOS screen shows the iPad view when the window is wide (`horizontalSizeClass == .regular`), so Split View, Slide Over and Stage Manager get the right layout. Add an iPad view only when its layout differs.
- Screens that haven't moved yet are still in `Arcfin/Screens/`, with `#if os(...)` inside. They move one at a time.
- **New files in a platform folder** need that platform set in the project: in Xcode, select the file and under Target Membership choose only that platform (Xcode filters platforms per file, not per folder). `.gitea/scripts/check-platform-folders.py --fix` sets it for every file at once, and CI fails while one is missing.

## Branches

| Branch | Purpose |
|---|---|
| `main` | The only long-lived branch. Everything merges here through pull requests, and it should always build and run |
| `feat/…`, `fix/…`, `docs/…`, `ci/…`, `l10n/…` | Your work, branched from an up-to-date `main` |
| `hotfix/…` | An urgent fix for a build already on TestFlight, branched from that build's tag |

Branch from `main` and open your pull request against `main`.

**Releases** aren't branches. A release is a small pull request that sets the version and build number, followed by signed tags on the merged commit, one per platform (for example `iOS-0.3.0-build-1`). The tags mark exactly what shipped.

## Pull requests

1. **One change per pull request.** Separate unrelated fixes.
2. **Fill in the template.** Say *why* as well as *what*, link the issue (`Fixes #123`), and say how you tested it, including the platforms.
3. **Sign off every commit** (`git commit -s`). See [License and the DCO](#license-and-the-dco).
4. **Keep commits meaningful:** a short, plain-English subject line ("Library: remember the sort order per library"). Each commit should build.
5. **CI must pass:** package tests, the three platform builds, the String Catalog check, the Release build and the sign-off check.
6. **Review:** the maintainer reviews and merges every pull request.

## AI-assisted contributions

You're welcome to use AI tools, as the maintainer does. If you do:

- **You're the author.** Understand every line you submit, and be ready to explain and change it in review.
- **Test it yourself.** Build and run the change; don't rely on the tool's word that it works.
- **Say so** in the pull request description if a large part of the change was generated.
- **Keep the same standard** as hand-written code: the conventions above, tests, and a focused change.
- **Mind the license.** Don't submit generated code you have reason to think copies someone else's work.

Pull requests that look generated and untested will be closed.

---

## Translating Arcfin

Translations come in as pull requests, like any other change. All you need is a Mac with Xcode 26 or later; no account anywhere else.

### Before you start

Open a **Translation** issue saying which language you'd like to do. It saves two people translating the same language, and it's where questions about wording can go.

### Where the text lives

| File | What's in it |
|---|---|
| `Arcfin/Localizable.xcstrings` | Everything in the app |
| `ArcfinWidgets/Localizable.xcstrings` | Widgets and Live Activities |
| `Arcfin/InfoPlist.xcstrings` | Permission prompts (Bluetooth, Face ID, Local Network, Location) |
| `Arcfin/Intents/AppShortcuts.xcstrings` | Siri and Shortcuts phrases |

English is the source language. Don't edit the English text in these files; if the English is wrong or unclear, say so in your issue.

### Adding a language

1. In Xcode, select the **Arcfin** project, then **Info › Localizations**, and click **+** to add your language. Xcode adds a column for it to every catalog above.
2. Open each `.xcstrings` file, pick your language in the sidebar, and translate. Mark an entry **Reviewed** once you're happy with it.
3. Build and run with your language: **Product › Scheme › Edit Scheme › Run › Options › App Language**, or choose it in Arcfin's **Settings › Language**. Check the screens you translated on as many platforms as you can (iPhone, iPad, Mac, Apple TV).

### Guidelines

- **Keep placeholders** such as `%@`, `%lld` and `${applicationName}` exactly as they are. You can move them; use `%1$@`, `%2$@` if your language needs them in a different order.
- **Plurals:** if a string has a number in it, use **Vary by Plural** so each plural form of your language reads correctly.
- **Use Apple's wording** for system features (Picture in Picture, AirPlay, SharePlay, Face ID and so on), as your language's version of iOS shows them.
- **Don't translate names:** Arcfin, Jellyfin, Seerr, and the player engine names Aether, AVFoundation and VLC.
- **Keep it short.** Labels sit on buttons, tabs and Apple TV cards. If a translation won't fit, a shorter word beats a cut-off one.
- **Siri phrases:** give a few natural ways to say each one. Every phrase must include `${applicationName}`, and `${target}` where the English has it.

### When a language ships

A language is merged once it's **at least 90% translated** and has been **read through by a second speaker** of that language. Anything still untranslated shows in English. Until then, keep the work in a draft pull request; it can be updated as new text is added.

Fixes to an existing translation are welcome as small pull requests at any time.

### Languages that need a reviewer

The first versions of these languages were machine translated so they could ship sooner, and no native speaker has read them yet: German, French, Spanish, Simplified Chinese, Brazilian Portuguese, Japanese, Italian, Korean, Dutch and Russian. Every entry in them is marked **Needs Review** in Xcode. They're exempt from the second-speaker rule above.

If you speak one of them, filter a catalog to **Needs Review**, fix what reads wrong and mark the rest **Reviewed**. A pull request covering part of a language is fine. Plurals especially need a look: these first versions avoid **Vary by Plural**, so strings with a number may read stiffly.

---

## Reporting bugs

Use the [Bug Report template](https://git.psmattas.com/ArcFin/ArcFin/issues/new/choose), or **Settings › About › Report a Problem** in the app. Please include:

- what you did, what you expected and what happened instead;
- the device, OS version, Arcfin version and build, and the playback engine if it's about playback;
- your Jellyfin server version if it's relevant;
- a **diagnostics file** from **Settings › About › Share Diagnostics**, if you can. It can contain your server's address and the titles you played, so check it before attaching it to a public issue.

Search [existing issues](https://git.psmattas.com/ArcFin/ArcFin/issues) first. Security problems go by email, not as issues; see [SECURITY.md](SECURITY.md).

---

## License and the DCO

Arcfin is licensed under [AGPL-3.0-or-later](LICENSE). By contributing, you license your contribution under the same terms. You keep the copyright on your own work; there's no CLA and no copyright assignment.

Every commit needs a **Developer Certificate of Origin** sign-off: a `Signed-off-by:` line certifying that you wrote the change, or otherwise have the right to submit it under the project's license ([developercertificate.org](https://developercertificate.org)). Add it with:

```sh
git commit -s
```

To sign off commits you've already made on your branch:

```sh
git rebase --signoff main
```

The Arcfin name and logo aren't covered by the code license. If you're forking rather than contributing back, see [TRADEMARK.md](TRADEMARK.md).

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md) in issues, pull requests and reviews.

# Contributing

Contributions are welcome. Arcfin is still maintained day-to-day by one
person, so response times won't always be fast, but PRs and issues from
anyone are genuinely wanted.

## License and the DCO

Arcfin is licensed under [AGPL-3.0-or-later](LICENSE). Every commit needs a
**Developer Certificate of Origin (DCO)** sign-off — a `Signed-off-by:`
trailer certifying you wrote the change (or otherwise have the right to
submit it under the project's license). Add it automatically with:

```
git commit -s
```

No CLA, no copyright assignment — you keep copyright on your own
contributions. Signing off just licenses your contribution to the project
under the same AGPL-3.0-or-later terms as the rest of the codebase. PRs
without a sign-off will be asked to add one before merge.

The "Arcfin" name and logo aren't covered by the code license — see
[TRADEMARK.md](TRADEMARK.md) if you're forking rather than contributing back.

---

## Getting Started

1. Clone the repo and open `Arcfin.xcodeproj` in Xcode 26+.
2. Local packages live in `LocalPackages/` and are already wired into the project — no manual "Add Package Dependencies" step needed.
3. Build target: **Arcfin** on a simulator or device running iOS 26.

### Stack

See the [README](README.md#architecture) for the full stack and architecture overview.

### Code Standards

- **Swift 6** strict concurrency — all code must compile without warnings.
- **SwiftUI only** — no UIKit unless absolutely forced by a system API.
- **Plain `@Observable` classes** for state and side effects — not TCA, despite it being a dependency (see the README's Stack table).
- **No comments** unless the WHY is non-obvious. No docstrings, no inline narration.
- **Tests use Swift Testing**, not XCTest. Every new feature should have corresponding tests.

### Branching

- `main` — stable, always buildable
- `v{major}.{minor}.{patch}` — active development branch
- Feature work branches off the current version branch, not `main`

### Pull Requests

- One concern per PR.
- PR description must explain **why**, not just **what**.
- All CI checks must pass before merge.
- Maintainer reviews all PRs before merge.

### AI-Assisted Code

AI tools (Claude Code) are used for assistive coding. All AI-generated code is reviewed by the maintainer before merge. See the README for the project's AI use policy.

---

## Translating Arcfin

Translations come in as pull requests, like any other change. All you need
is a Mac with Xcode 26 or later; no account anywhere else.

### Before you start

Open a **Translation** issue saying which language you'd like to do. It
saves two people translating the same language, and it's where questions
about wording can go.

### Where the text lives

| File | What's in it |
|---|---|
| `Arcfin/Localizable.xcstrings` | Everything in the app |
| `ArcfinWidgets/Localizable.xcstrings` | Widgets and Live Activities |
| `Arcfin/InfoPlist.xcstrings` | Permission prompts (Bluetooth, Face ID, Local Network, Location) |
| `Arcfin/Intents/AppShortcuts.xcstrings` | Siri and Shortcuts phrases |

English is the source language. Don't edit the English text in these
files; if the English is wrong or unclear, say so in your issue.

### Adding a language

1. In Xcode, select the **Arcfin** project, then **Info › Localizations**,
   and click **+** to add your language. Xcode adds a column for it to every
   catalog above.
2. Open each `.xcstrings` file, pick your language in the sidebar, and
   translate. Mark an entry **Reviewed** once you're happy with it.
3. Build and run with your language: **Product › Scheme › Edit Scheme ›
   Run › Options › App Language**. Check the screens you translated on as
   many platforms as you can (iPhone, iPad, Mac, Apple TV).

### Guidelines

- **Keep placeholders** such as `%@`, `%lld` and `${applicationName}`
  exactly as they are. You can move them; use `%1$@`, `%2$@` if your
  language needs them in a different order.
- **Plurals**: if a string has a number in it, use **Vary by Plural** so
  each plural form of your language reads correctly.
- **Use Apple's wording** for system features (Picture in Picture, AirPlay,
  SharePlay, Face ID and so on), as your language's version of iOS shows
  them.
- **Don't translate names**: Arcfin, Jellyfin, Seerr, and the player engine
  names Aether, AVFoundation and VLC.
- **Keep it short.** Labels sit on buttons, tabs and Apple TV cards. If a
  translation won't fit, a shorter word beats a cut-off one.
- **Siri phrases**: give a few natural ways to say each one. Every phrase
  must include `${applicationName}`, and `${target}` where the English has
  it.

### When a language ships

A language is merged once it's **at least 90% translated** and has been
**read through by a second speaker** of that language. Anything still
untranslated shows in English. Until then, keep the work in a draft pull
request; it can be updated as new text is added.

Fixes to an existing translation are welcome as small pull requests at any
time.

### Languages that need a reviewer

The first versions of these languages were machine translated so they could
ship sooner, and no native speaker has read them yet: German, French,
Spanish, Simplified Chinese, Brazilian Portuguese, Japanese, Italian,
Korean, Dutch and Russian. Every entry in them is marked **Needs Review** in
Xcode. They're exempt from the second-speaker rule above.

If you speak one of them, filter a catalog to **Needs Review**, fix what
reads wrong and mark the rest **Reviewed**. A pull request covering part of
a language is fine. Plurals especially need a look: these first versions
avoid **Vary by Plural**, so strings with a number may read stiffly.

As with every commit, translation commits need a DCO sign-off
(`git commit -s`).

---

## Reporting Issues

Open a Gitea issue with:
- Steps to reproduce
- Expected vs. actual behavior
- Xcode version, OS version, device/simulator

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

## Reporting Issues

Open a Gitea issue with:
- Steps to reproduce
- Expected vs. actual behavior
- Xcode version, OS version, device/simulator

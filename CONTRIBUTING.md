# Contributing

Arcfin is a private project maintained by a single developer. External contributions are not accepted at this time.

This file is here for maintainability as the project matures.

---

## If You Are a Collaborator

### Getting Started

1. Clone the repo and open `Arcfin.xcodeproj` in Xcode 26+.
2. Add local packages: **File → Add Package Dependencies → Add Local** → select `Packages/`.
3. Build target: **Arcfin** on a simulator or device running iOS 26.

### Stack

See `CLAUDE.md` for the full locked stack and architecture overview.

### Code Standards

- **Swift 6** strict concurrency — all code must compile without warnings.
- **SwiftUI only** — no UIKit unless absolutely forced by a system API.
- **TCA** for all state and side effects.
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

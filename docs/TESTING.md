# Testing Arcfin

Arcfin isn't on the App Store yet. It's in beta on TestFlight, in two groups: a small internal beta that gets every new build first, and a public beta that anyone can join. You need your own [Jellyfin](https://jellyfin.org) server, or an account on one.

- [Public beta](#public-beta)
- [Internal beta](#internal-beta)
- [How releases work](#how-releases-work)
- [Reporting a problem](#reporting-a-problem)
- [Thank you, testers](#thank-you-testers)

## Public beta

Anyone can join on **[TestFlight](https://testflight.apple.com/join/kkC58n2w)**. Install TestFlight from the App Store, open the invite on your iPhone, iPad, Mac or Apple TV, and you'll get each new build automatically.

Public builds go through Apple's TestFlight review first. A new version usually takes 1 to 3 days; a new build of an existing version is usually through within a day, but can take as long. The [release notes](https://git.psmattas.com/ArcFin/ArcFin/releases) list what's in each build.

## Internal beta

Internal testers get a **nightly build**. Every night at midnight Irish time, if anything has changed since the last one, Arcfin builds the newest code and sends it to them on iPhone, iPad, Mac and Apple TV. They test it first: once a nightly has held up and they've approved it, that build goes on to the public beta.

- **Apple checks every nightly first.** Most get through within a few hours, depending on how quickly Apple's reviewers get to them, so a nightly often arrives in the morning rather than at midnight.
- **A new version takes longer.** The first build of each new version gets Apple's full review, which usually takes 1 to 3 days. After a version change, nightlies can wait in line until Apple approves it.
- **Sometimes there's more than one a day,** when an urgent fix can't wait until midnight.
- **Seats are limited.** To ask for one, email **[support.arcfin@psmattas.com](mailto:support.arcfin@psmattas.com)** with the Apple Account email to invite and the devices you'd test on.
- **Expect rough edges.** Internal builds are the newest and least tested.

## How releases work

**Until the App Store release**

- **0.5.0** brings the last big batch of features.
- **0.5.1** is the last beta. It adds no new features: it's for stability fixes, and tests covering everything Arcfin does.
- Once testers are happy with 0.5.1, it goes to Apple for review. When Apple approves it, that build is Arcfin's first App Store release.

**After the App Store release**

Arcfin moves to a rolling cycle. New features and improvements go through three stages:

1. **Nightly builds** go to the [internal beta](#internal-beta) every night something has changed. Anyone can ask for a seat.
2. **Approved nightlies** go to the [public beta](#public-beta) on TestFlight, once the internal testers have used a nightly and approved it. It's the same invite link, so nothing changes if you've already joined.
3. **App Store updates** reach everyone once both beta groups have used a build without problems.

The same build moves through all three: nothing is rebuilt on the way to the App Store. Every build has a pre-release on the [Releases](https://git.psmattas.com/ArcFin/ArcFin/releases) page with what changed, and a build that reached the App Store is a full release there.

**Security fixes** skip the wait. They go out as fast as the targets in [SECURITY.md](../SECURITY.md#what-happens-next), on TestFlight and on the App Store.

## Reporting a problem

Use **Settings › About › Report a Problem** in the app, or [open an issue](https://git.psmattas.com/ArcFin/ArcFin/issues/new/choose). Please include:

- your device and OS version;
- your Jellyfin server version (**Settings › Server**);
- the build you're on (**Settings › About**);
- what you did right before it happened.

Screen recordings help a lot for anything visual. **Settings › About › Share Diagnostics** makes a text file of the app's log to attach. It can include your server's address and the titles you played, so look it over before posting it publicly.

## Thank you, testers

Between 100 and 150 people have been testing Arcfin on TestFlight, reporting bugs and suggesting ideas. Arcfin wouldn't be what it is without you. Thank you.

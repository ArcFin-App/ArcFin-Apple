# Security Policy

Thank you for helping keep Arcfin and the people who use it safe.

## Reporting a vulnerability

**Please don't report security problems in a public issue, pull request or discussion.**

Email **[security@psmattas.com](mailto:security@psmattas.com)** with:

- what the problem is and what an attacker could do with it;
- the steps to reproduce it, or a proof of concept;
- the Arcfin version and build, the platform and the OS version;
- your Jellyfin or Seerr server version, if it's involved;
- how you'd like to be credited, or that you'd rather stay anonymous.

If the report contains sensitive details, say so in your first email and we can agree on how to send them.

## What happens next

| Step | Target |
|---|---|
| Acknowledgement of your report | Within 48 hours |
| First assessment: confirmed or not, and how severe | Within 7 days |
| A fix on TestFlight for a confirmed critical or high-severity problem | Within 30 days |
| A fix for other confirmed problems | In a following release, usually within 90 days |

Arcfin is maintained by one person, so these are targets rather than guarantees. You'll get an update at least every two weeks until the report is closed.

## Disclosure

Arcfin follows coordinated disclosure.

- Please give us a reasonable time to ship a fix before you publish anything, normally **90 days** from your report, or sooner once a fix is on TestFlight.
- Once the fix has shipped, we publish the details in the release notes and credit you, unless you'd rather we didn't.
- If a problem is being actively exploited, we may disclose it sooner so people can protect themselves.

## Safe harbour

We won't take legal action against anyone who, in good faith:

- tests only against their own devices, accounts and servers, or ones they have permission to test;
- doesn't access, change or keep other people's data, and stops as soon as they reach any;
- doesn't degrade or disrupt servers or services, including Jellyfin, Seerr or TMDB;
- reports the problem to us privately and gives us time to fix it.

This covers Arcfin only. Servers and services that Arcfin connects to have their own policies.

## Supported versions

Only the **latest build on TestFlight** gets security fixes. Older builds and versions don't; TestFlight updates testers automatically.

| Version | Supported |
|---|---|
| Latest TestFlight build | Yes |
| Older builds | No |

## Scope

**In scope:**
- the Arcfin app on iPhone, iPad, Mac and Apple TV, its widgets and Top Shelf extension, and the source code in this repository;
- exposure of credentials or tokens: Jellyfin access tokens, Seerr passwords, the TMDB key, or custom request headers;
- secrets stored insecurely, outside the Keychain;
- weakened TLS or certificate validation, or traffic sent somewhere it shouldn't go;
- data from a server or API being run, rendered or trusted unsafely;
- privacy leaks of watch history, server addresses or diagnostics to anyone you didn't choose;
- bypassing a profile's PIN, Face ID or Touch ID lock, parental controls or access schedule.

**Out of scope:**
- vulnerabilities in Jellyfin, Seerr, TMDB or other services themselves. Please report those to their projects;
- attacks that need an unlocked device in the attacker's hands, or a jailbroken or compromised device;
- social engineering, phishing and denial of service;
- missing best practices with no practical exploit;
- reports from automated scanners without a demonstrated impact.

## How Arcfin protects your data

- **No analytics, tracking or crash-reporting SDKs.** The developer runs no servers that receive your data.
- **Secrets in the Keychain:** server access tokens, the Seerr password, the TMDB key and custom request headers.
- **Direct connections:** the app talks straight from your device to the servers you add, using the system's TLS and certificate validation.
- **Diagnostics stay on your device.** Share Diagnostics only creates a file when you ask, and only you decide where it goes.
- **Profile locks:** a PIN, Face ID or Touch ID protects a profile, and Jellyfin's parental controls and access schedule are applied in the app.

## Questions

For anything that isn't a vulnerability, see [Get in touch](README.md#get-in-touch) or email [support.arcfin@psmattas.com](mailto:support.arcfin@psmattas.com).

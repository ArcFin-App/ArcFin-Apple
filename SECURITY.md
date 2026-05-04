# Security Policy

## Supported Versions

Only the latest release on `main` is actively supported.

| Version | Supported |
|---|---|
| Latest (`main`) | Yes |
| Older branches | No |

## Reporting a Vulnerability

**Do not open a public Gitea issue for security vulnerabilities.**

Report privately to: **security@psmattas.com**

Include in your report:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if you have one)

You will receive an acknowledgement within 48 hours. If the vulnerability is confirmed, a fix will be prioritised and you will be credited (unless you prefer anonymity).

## Scope

Security issues relevant to Arcfin include:

- Credential or token exposure (Jellyfin auth tokens, API keys)
- Keychain misuse or insecure storage of secrets
- Network traffic interception / missing TLS validation
- Unvalidated data from external APIs being executed or rendered unsafely
- Privacy leaks (watch history, server URLs) to third parties

## Out of Scope

- Vulnerabilities in Jellyfin server, Jellyseerr, or Streamystats themselves
- Issues requiring physical device access
- Theoretical attacks with no practical exploit path

## Disclosure Policy

Coordinated disclosure. Once a fix is released, the vulnerability may be publicly disclosed with credit to the reporter.

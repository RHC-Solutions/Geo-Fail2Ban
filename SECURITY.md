# Security Policy

## Supported Versions

Geo-Fail2Ban is distributed from `main`. Security fixes land there, and the
supported version is the latest commit — there are no maintained release
branches.

| Version | Supported |
| ------- | --------- |
| `main` (latest) | :white_check_mark: |
| Older checkouts | :x: — pull and re-run `install.sh` |

Re-running `sudo bash install.sh` upgrades an existing installation in place and
preserves your `/etc/geo-fail2ban.conf` credentials.

## Reporting a Vulnerability

**Please do not open a public issue for a security problem.**

Report privately through GitHub: open the repository's **Security** tab and use
**Report a vulnerability** (private vulnerability reporting). If that is
unavailable, contact us via [rhcsolutions.com](https://rhcsolutions.com) or
[t.me/rhcsolutions](https://t.me/rhcsolutions) and ask for a private channel
before sending details.

Please include:

- What the issue is and the impact you believe it has
- The affected file(s) and, where relevant, the commit you tested
- Steps to reproduce, or a proof of concept
- Your OS/distro, firewall backend (firewalld/ufw/iptables) and fail2ban version

### What to expect

- **Acknowledgement** within 5 working days.
- **An initial assessment** — accepted, needs more information, or declined
  with reasoning — within 14 days.
- **Progress updates** at least every 14 days while a fix is in development.
- **Credit** in the commit or release notes when a report is accepted, unless
  you would rather stay anonymous.

If a report is declined we will explain why. If we disagree about severity we
will say so plainly rather than letting the report go quiet.

## Scope Notes

This project configures firewall rules, ipsets and fail2ban jails as root, and
holds third-party API credentials. Findings that are especially in scope:

- Anything allowing an unprivileged user to influence what gets banned,
  unbanned, or whitelisted
- Command or configuration injection via API responses, log lines, or values in
  `/etc/geo-fail2ban.conf`
- Credential exposure — `/etc/geo-fail2ban.conf` should be mode 0600, and
  tokens should not reach logs or process listings
- Firewall rules that fail open, or a lockout with no recovery path

Out of scope: vulnerabilities in fail2ban, ipset, iptables, firewalld or ufw
themselves (report those upstream), and the inherent behaviour of blocking
whole countries via `GEOBLOCK_COUNTRIES`.

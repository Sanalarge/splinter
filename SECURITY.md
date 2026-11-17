# Security policy

Security fixes target the latest release. Please update before reporting an issue.

Report vulnerabilities privately through
[GitHub security advisories](https://github.com/Sanalarge/splinter/security/advisories/new).
Include the affected version, macOS version, reproduction steps and expected
impact. Do not publish credentials, raw input logs or exploit details in a public issue.

Splinter needs Accessibility and Input Monitoring to intercept and remap input.
It processes input locally and does not upload events. Diagnostic logs may
contain key names, shortcuts and hardware identifiers. Review them before sharing.

Repository workflows use read-only permissions by default. Only the main-branch
release job can create tags and releases. Pull request jobs do not receive release
credentials, and Actions dependencies are pinned to full commit hashes.

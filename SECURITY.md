# Security policy

## Supported versions

Security fixes are made on `main` and included in the next tagged release.
Workstation automation should install a tagged release rather than a floating
branch.

## Reporting a vulnerability

Do not open a public issue for suspected vulnerabilities, exposed credentials,
or unsafe agent instructions. Use GitHub's private vulnerability reporting for
this repository. If that is unavailable, use the encrypted contact method at
<https://jamesernet.com/contact/>.

Useful reports identify the affected release, the trust boundary crossed, the
impact, and the smallest reproducible example that does not contain client data
or live credentials.

## Scope

The highest-risk surfaces are installation scripts, generated agent settings,
tool hooks, repository-policy enforcement, skill instructions that invoke tools,
and the third-party content selected by `vendor.lock.json`.

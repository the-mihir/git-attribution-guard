# Security policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's private reporting:
**Security > Report a vulnerability** on
https://github.com/the-mihir/git-attribution-guard/security/advisories/new

Include the version (`attribution version`), your OS/shell, and steps to
reproduce. You should get an answer within 7 days. Fixes are released as a
patch version and credited in the advisory unless you ask otherwise.

## Scope and design

git-attribution-guard runs as git hooks in every repository where it is active,
so it treats commit messages, author identities and config values as untrusted:

- No `eval`; all expansions are quoted; regexes and emails reach `awk` through
  `ENVIRON` (no escape processing, no code injection into the awk program).
- Temporary files are created with `mktemp` under `umask 077` and removed.
- JSON settings are parsed by jq/node/python, written to a temp file and moved
  into place; invalid JSON is left untouched.
- No network access and no telemetry. Release archives are built by CI from the
  tagged commit and published with `SHA256SUMS`.
- History rewrite needs a dry run, a clean tree, backup refs and typed confirmation;
  force pushes are printed, never executed.

Out of scope: hooks are a client-side control. Anyone can skip them with
`--no-verify` or by committing on another machine. Use the CI check in
`examples/attribution-check.yml` for enforcement.

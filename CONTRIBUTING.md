# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Setup

```sh
git clone https://github.com/OWNER/git-attribution-guard.git
cd git-attribution-guard
make check            # needs shellcheck; git-filter-repo enables the rewrite tests
```

Tests never touch your real configuration: every test gets a temporary `HOME`,
git config and repositories. Run one file with `sh tests/run.sh hooks`.

Try your working copy without installing: `./scripts/attribution status`.

## Rules for code

- POSIX `sh` and POSIX `awk` only. No bashisms, no `sed -i`, no `readlink -f`,
  no GNU-only flags. CI runs the suite with `sh` and `dash` on Linux and macOS.
- Quote every expansion. Pass user data to `awk` through `ENVIRON`, never `-v`
  (it interprets backslashes) and never by building program text.
- Nothing destructive without confirmation; back up any file before changing it.
- No network access and no telemetry in the tool.
- A new AI tool pattern goes in `scripts/patterns.sh` with a test in
  `tests/test_modes.sh` that shows a real trailer line.
- Update `README.md`, `SKILL.md` and the `[Unreleased]` section of
  `CHANGELOG.md` when behaviour changes.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`,
  `docs:`, `test:`, `ci:`, `chore:`, `refactor:`.
- No `Co-authored-by` or "Generated with" lines for AI tools (the project dogfoods itself).

## Releases

Maintainers follow [docs/RELEASING.md](docs/RELEASING.md).

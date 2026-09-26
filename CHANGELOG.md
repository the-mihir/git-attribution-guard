# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-09-26

### Added
- `attribution` CLI (POSIX sh): `install`, `uninstall`, `status`, `on`/`off`, `mode`,
  `allow`, `author`, `check`, `rewrite`, `doctor`.
- Git hooks: `commit-msg` (filters trailers), `pre-commit` (author check, AI author
  block), `pre-push` (blocks disallowed attribution, catches `--no-verify` commits).
- Modes `strip-ai`, `allowlist`, `strip-all`, `off`; global defaults with per-repo
  overrides through native git config.
- Hook chaining: repository `.git/hooks`, a previous global `core.hooksPath`, and
  Husky-style local `core.hooksPath` integration. Pass-through stubs keep every
  other repository hook (git-lfs, etc.) working.
- Claude Code integration: turns off Claude Code attribution in `settings.json`
  (jq, node or python3), optional CLAUDE.md / AGENTS.md instructions, and a skill.
- History rewrite with `git filter-repo`: dry run, backup refs, typed confirmation,
  mailmap support, `origin` remote preserved.
- CI check example for enforcing attribution on pull requests.

[Unreleased]: https://github.com/OWNER/git-attribution-guard/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/OWNER/git-attribution-guard/releases/tag/v1.0.0

# git-attribution-guard

[![CI](https://github.com/OWNER/git-attribution-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/git-attribution-guard/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/OWNER/git-attribution-guard)](https://github.com/OWNER/git-attribution-guard/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

You decide who appears as author, co-author and contributor on your commits and on GitHub.

AI tools (Claude Code, Copilot, Cursor, Codex, Gemini, Aider, Devin, Windsurf,
Amazon Q, Tabnine, bots) often add `Co-authored-by:` trailers or
"Generated with ..." lines, and GitHub then lists them as contributors.
git-attribution-guard stops that at the **git** level with hooks, so it works for
every tool that commits, not only Claude Code.

- Turn it on or off, globally or per repository.
- Choose a mode: remove AI co-authors only, keep an allowlist, or remove all co-authors.
- Enforce your own author name and email.
- Block pushes that still contain disallowed attribution (this catches `--no-verify`).
- Clean up past history on request, with a dry run, backups and confirmation.
- Includes a Claude Code skill and turns off Claude Code's own attribution.

POSIX `sh` + `awk` only. Runs on macOS, Linux and Git Bash for Windows.
No network access, no telemetry.

## Install

Requirements: git 2.9+. Optional: `jq`, `node` or `python3` (to edit Claude Code
settings), [`git-filter-repo`](https://github.com/newren/git-filter-repo) (only for `rewrite`).

From a release (recommended; checksum verified):

```sh
v=1.0.0
curl -fsSLO https://github.com/OWNER/git-attribution-guard/releases/download/v$v/git-attribution-guard-$v.tar.gz
curl -fsSLO https://github.com/OWNER/git-attribution-guard/releases/download/v$v/SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS   # macOS: shasum -a 256 -c --ignore-missing SHA256SUMS
tar xzf git-attribution-guard-$v.tar.gz
sh git-attribution-guard-$v/install.sh
```

From a clone:

```sh
git clone https://github.com/OWNER/git-attribution-guard.git
cd git-attribution-guard
./install.sh                 # global: all your repositories
```

`install.sh` does four things, and running it again changes nothing:

1. Copies the CLI and hooks to `~/.local/share/git-attribution-guard/` and puts an
   `attribution` command in `~/.local/bin/` (add it to `PATH` if needed).
2. Installs the Claude Code skill to `~/.claude/skills/git-attribution-guard/`.
3. Sets the global `core.hooksPath` to the guard's hooks (existing hooks keep working, see below).
4. Sets `"attribution": {"commit": "", "pr": ""}` and `"includeCoAuthoredBy": false` in
   `~/.claude/settings.json`, after a timestamped backup.

Options: `--local` (current repository only), `--prefix DIR`, `--bin-dir DIR`,
`--no-skill`, `--no-configure`, `--agent-instructions`, `--uninstall`. See `./install.sh --help`.

Check the result:

```sh
attribution status
attribution doctor
```

## Usage

```sh
attribution status                                   # what applies here, and why
attribution off --local                              # disable in this repo only
attribution mode allowlist --local                   # only allowed co-authors here...
attribution allow add pritom@example.com --local     # ...namely Pritom
attribution allow add @mycompany.com                 # allow a whole domain
attribution mode strip-all                           # never any co-authors
attribution author set "Mihir" mihir@example.com     # block commits from any other identity
attribution check                                    # read-only audit of the current branch
attribution check origin/main..HEAD                  # audit a range (exit 1 on findings)
attribution rewrite --dry-run                        # preview cleaning past commits
attribution rewrite --mailmap .mailmap --dry-run     # preview fixing old author emails
```

Every setting command takes `--global` (default) or `--local`. `attribution <command> --help` shows details.

### Modes

| Mode | Co-authored-by / Co-developed-by | AI Signed-off-by / Assisted-by | "Generated with" AI lines |
|---|---|---|---|
| `strip-ai` (default) | removes AI/bot, keeps humans | removed | removed |
| `allowlist` | keeps only `attribution.allow` emails | removed | removed |
| `strip-all` | removes all | removed | removed |
| `off` | untouched | untouched | untouched |

Human `Signed-off-by` lines are never touched. Emails in `attribution.allow` always
win over AI detection (useful if a human teammate is literally called "Claude").

### Configuration (plain git config)

| Key | Default | Meaning |
|---|---|---|
| `attribution.enabled` | `true` | master switch |
| `attribution.mode` | `strip-ai` | see above |
| `attribution.allow` | none | multi-value; allowed co-author emails, or `@domain` |
| `attribution.authorName` / `attribution.authorEmail` | none | expected commit author |
| `attribution.blockPush` | `true` | pre-push check |
| `attribution.extraPatterns` | none | multi-value; extra ERE patterns for AI/bot identities |

`--local` values override `--global` values. Multi-value keys (`allow`,
`extraPatterns`) combine global and local entries.

Built-in AI/bot patterns live in one file:
[`scripts/patterns.sh`](scripts/patterns.sh). Add your own without editing it:

```sh
git config --global --add attribution.extraPatterns '\bmy-agent\b'
attribution doctor     # validates the regex
```

## How it works

| Hook | Does |
|---|---|
| `commit-msg` | rewrites the message according to the mode (idempotent; leaves the diff part of `git commit -v` alone) |
| `pre-commit` | blocks an AI/bot author, and a mismatch with `attribution.authorName/Email` |
| `pre-push` | scans every commit being pushed (new branches, updates; ignores deletions) and blocks disallowed authors or co-authors, including commits made with `--no-verify` or by tools that skip `commit-msg` (rebase, cherry-pick) |

**Existing hooks keep working.** A global `core.hooksPath` normally disables every
repository's `.git/hooks`. The guard avoids that:

- Its hooks run the repository's own `.git/hooks/<name>` afterwards (arguments,
  stdin and exit code passed through). Pass-through stubs exist for all other
  client hooks, so git-lfs, Gerrit `Change-Id` and similar hooks still run.
- If you already had a global `core.hooksPath`, it is remembered and chained, and
  restored on uninstall.
- Repositories with their **own** `core.hooksPath` (Husky, custom `.githooks`)
  override the global one, so the guard would silently not run. `attribution status`
  and `attribution doctor` detect this; `attribution install --local` then adds a
  small marked block to that system's hooks (for Husky: `.husky/commit-msg`,
  `.husky/pre-commit`, `.husky/pre-push`) instead of replacing anything. The block
  calls `attribution` only if it is installed, so teammates without it are unaffected.
- No existing file is overwritten: modified files are backed up first, and
  `attribution uninstall --local` removes only the marked block.

## Cleaning past history

Only when you ask for it; it never runs automatically.

```sh
attribution rewrite --dry-run                    # 1. preview: which commits, which lines
attribution rewrite                              # 2. type 'rewrite' to confirm
attribution check                                # 3. verify
git push --force-with-lease --all origin         # 4. you run these yourself
git push --force-with-lease --tags origin
```

`rewrite` requires a clean working tree and `git filter-repo`. It saves backup refs
under `refs/attribution-backup/<timestamp>/`, keeps the `origin` remote, and
prints (never runs) the push commands. Default range: the current branch.

- Fix old author names/emails: create a mailmap (`Proper Name <proper@x> <old@x>`)
  and run `attribution rewrite --mailmap <file>`.
- After a force push, collaborators must re-clone or hard reset.

## Claude Code

- `install` turns off Claude Code's own trailers in `settings.json` (global:
  `~/.claude/settings.json`, local: `.claude/settings.json`). Other keys are kept,
  a backup is made, and `uninstall` restores the previous values.
- `--agent-instructions` adds a short marked section to `~/.claude/CLAUDE.md`
  (global) or the repository's `CLAUDE.md` / `AGENTS.md` (local).
- The skill (`SKILL.md`) tells Claude to check `attribution status` before
  committing, to map requests such as "only Pritom can be co-author here" to
  commands, and never to rewrite history or force push without your confirmation.

The hooks are the real guarantee; the settings and instructions only reduce noise.

## Enforce on GitHub too

Local hooks run only on machines where they are installed. Copy
[`examples/attribution-check.yml`](examples/attribution-check.yml) to
`.github/workflows/` in your repository and make it a required status check.

## Limitations

- **Squash and merge commits made on github.com** are created server-side. GitHub
  may add `Co-authored-by` trailers for every commit author in the PR. Local hooks
  cannot see these; edit the message in the merge dialog, and use the CI check to detect them afterwards.
- **Already-pushed history** only changes with `attribution rewrite` plus a force push.
- **GitHub contributor stats** refresh with a delay (hours to days) after a rewrite.
- **`--no-verify`** skips local hooks. `git push --no-verify` skips the pre-push check too; the CI check is the backstop.
- **Pattern matching is heuristic.** Allow false positives with `attribution allow add`; add missing tools with `attribution.extraPatterns` (and please open an issue).
- **Commits made by other people's machines** are outside your hooks; use the CI check.

## Uninstall

```sh
attribution uninstall --local          # per repository
./install.sh --uninstall               # everything the installer added
```

Your `attribution.*` preferences stay in git config; remove them with
`git config --global --remove-section attribution`.

## Development

```sh
make check      # ShellCheck + tests (tests use temporary HOME and repos)
make test       # tests only; rewrite tests are skipped without git-filter-repo
make dist       # release archives + SHA256SUMS
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and
[docs/RELEASING.md](docs/RELEASING.md) (publishing to GitHub and making releases).

## License

[MIT](LICENSE)

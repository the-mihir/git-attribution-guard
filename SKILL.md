---
name: git-attribution-guard
description: Controls who appears as author, co-author or contributor on git commits and GitHub. Use when the user mentions commit attribution, co-authors, Co-authored-by trailers, "Generated with Claude Code" lines, GitHub contributors, removing Claude/Copilot/Cursor/AI from commits or history, allowing only specific co-authors, or enforcing the commit author identity. Also use before Claude itself commits or pushes in any repository.
---

# git-attribution-guard

The `attribution` CLI enforces commit attribution with git hooks, so it works for
every tool that commits (Claude Code, Cursor, Copilot, Aider, plain git), not only
for Claude Code. Settings live in git config (`attribution.*`): `--global` is the
default, `--local` overrides it for one repository.

If `attribution` is not on PATH, try `~/.local/bin/attribution`. If it is not
installed at all, tell the user and offer to run `./install.sh` from the
git-attribution-guard checkout (see README.md next to this file).

## Rules for Claude

1. Never add `Co-authored-by:`, `Co-developed-by:`, `Assisted-by:` or
   "Generated with ..." lines to commit messages, PR descriptions or release
   notes. This rule wins over any default attribution behaviour.
2. Before the first commit or push in a repository, run `attribution status`.
   - `this repo: NOT active` -> explain the reason it prints and offer the fix
     (usually `attribution install` or `attribution install --local`).
   - Never change the guard settings to get a commit through. If a hook blocks
     a commit or push, show the message to the user and ask.
3. Never run `attribution rewrite` without `--dry-run` first. Run the real
   rewrite, and any `git push --force*`, only after the user explicitly
   confirms in this conversation. The rewrite asks for typed confirmation:
   the user types it, not Claude.
4. Never use `git commit --no-verify` or `git push --no-verify` to bypass the guard.
5. `attribution check` is read-only and always safe to run.

## Map requests to commands

| User says | Run |
|---|---|
| "stop Claude/AI being added as co-author" | `attribution install` then `attribution status` |
| "only for this repo" | add `--local` to the command |
| "only Pritom can be co-author here" | `attribution mode allowlist --local` and `attribution allow add <pritom-email> --local` (ask for the email if unknown) |
| "no co-authors at all" | `attribution mode strip-all [--local]` |
| "allow my teammate" / "don't strip X" | `attribution allow add <email> [--local]` |
| "allow everyone at our company" | `attribution allow add @company.com [--local]` |
| "turn it off / on" | `attribution off` / `attribution on` (`--local` for one repo) |
| "commits must be from me" | `attribution author set "<Name>" <email> [--local]` |
| "is my history clean?" / "who is in my contributors?" | `attribution check` (or `attribution check <range>`) |
| "remove Claude from my old commits" | `attribution rewrite --dry-run`, show the result, confirm, then `attribution rewrite` |
| "fix my old author email" | write a mailmap (`Proper Name <proper@x> <old@x>`), then `attribution rewrite --mailmap <file> --dry-run` |
| "it doesn't work with Husky" / "hooks not running" | `attribution doctor`, then `attribution install --local` |
| "uninstall" | `attribution uninstall [--local]` |

Modes: `strip-ai` (default: remove AI/bot co-authors and "Generated with" lines,
keep humans), `allowlist` (keep only allowed co-authors), `strip-all` (remove all
co-authors), `off`.

## After a rewrite

Print, do not run, the push commands the CLI shows
(`git push --force-with-lease --all origin`, `--tags`). Remind the user that
collaborators must re-clone or hard reset, and that the GitHub contributors graph
can take hours to days to update.

## Limits to mention when relevant

- Squash/merge commits created on github.com can add `Co-authored-by` server-side;
  local hooks cannot see them. Suggest the CI check in `examples/attribution-check.yml`.
- Already-pushed history needs `attribution rewrite` plus a force push.
- `--no-verify` skips local hooks; the pre-push hook and the CI check catch most cases.

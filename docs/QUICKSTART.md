## Quick start

**1. Install** (macOS, Linux, Git Bash on Windows)

```sh
v=__VERSION__
curl -fsSLO https://github.com/the-mihir/git-attribution-guard/releases/download/v$v/git-attribution-guard-$v.tar.gz
curl -fsSLO https://github.com/the-mihir/git-attribution-guard/releases/download/v$v/SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS      # macOS: shasum -a 256 -c --ignore-missing SHA256SUMS
tar xzf git-attribution-guard-$v.tar.gz
sh git-attribution-guard-$v/install.sh             # all repos; add --local for one repo
export PATH="$HOME/.local/bin:$PATH"               # if not already on PATH
```

**2. Check it works**

```sh
cd your-repo
attribution status      # "this repo: active" = protected
attribution doctor      # finds Husky / hooksPath conflicts and other problems
```

From now on, AI co-author lines (`Co-authored-by: Claude ...`, Copilot, Cursor, ...)
and "Generated with ..." lines are removed from every new commit, whichever tool makes it.
Human co-authors stay.

**3. Common tasks**

| I want to... | Command |
|---|---|
| see what applies in this repo | `attribution status` |
| turn it off / on in this repo | `attribution off --local` / `attribution on --local` |
| allow only one co-author in this repo | `attribution mode allowlist --local` then `attribution allow add friend@example.com --local` |
| never have any co-authors | `attribution mode strip-all` |
| block commits not made as me | `attribution author set "Your Name" you@example.com` |
| audit existing commits | `attribution check` |
| clean AI co-authors from old commits | `attribution rewrite --dry-run`, then `attribution rewrite` (needs `git-filter-repo`) |
| make it work with Husky | `attribution install --local` |
| uninstall | `sh git-attribution-guard-$v/install.sh --uninstall` |

Every command has `--help`. Settings are global by default; `--local` applies to the current repository only.

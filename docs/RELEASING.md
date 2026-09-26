# Publishing and releasing

## 1. First publish to GitHub (one time)

```sh
# Replace the OWNER placeholder with your GitHub user or organisation.
grep -rl OWNER --exclude-dir=.git . | xargs sed -i.bak 's/OWNER/your-github-name/g'
find . -name '*.bak' -not -path './.git/*' -delete

make check                     # lint + tests must pass

git init -b main               # skip if already a repository
git add -A
git commit -m "feat: initial release of git-attribution-guard"

# Create an EMPTY public repository named git-attribution-guard on github.com
# (no README / license / .gitignore), then:
git remote add origin git@github.com:your-github-name/git-attribution-guard.git
git push -u origin main
```

With the GitHub CLI instead of the web UI:

```sh
gh repo create your-github-name/git-attribution-guard --public --source . --push \
  --description "Control who appears as author/co-author on your git commits"
```

## 2. Repository settings (secure defaults)

In **Settings** on github.com:

| Setting | Value |
|---|---|
| Actions > General > Workflow permissions | **Read repository contents** (workflows ask for more only where needed) |
| Actions > General > Allow actions | GitHub-owned actions only (this repo uses only `actions/checkout`) |
| Code security > Private vulnerability reporting | **Enable** (SECURITY.md points here) |
| Code security > Dependabot alerts + security updates | Enable |
| Rules > Rulesets > branch `main` | Require PR, require status checks `ShellCheck` and `Tests (ubuntu-latest)` / `Tests (macos-latest)`, block force pushes |
| Rules > Rulesets > tags `v*` | Restrict creation, update and deletion to maintainers |
| General > Pull Requests | Allow squash merging; set the default commit message to "Pull request title and description" |

Tip: in GitHub squash merges, GitHub may append `Co-authored-by` lines for every
commit author in the PR. Check the message in the merge dialog.

## 3. Cutting a release

Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed.
It re-runs CI, checks that the tag, `VERSION` and `CHANGELOG.md` agree, builds
`.tar.gz` + `.zip` with `git archive`, writes `SHA256SUMS`, and creates the
GitHub Release page with notes taken from `CHANGELOG.md`.

```sh
git switch main && git pull --ff-only
# 1. Bump the version (Semantic Versioning: MAJOR.MINOR.PATCH)
echo 1.1.0 > VERSION
# 2. Move the [Unreleased] notes into a new "## [1.1.0] - YYYY-MM-DD" section
#    and update the compare links at the bottom of CHANGELOG.md
$EDITOR CHANGELOG.md
make check
make version-check TAG=v1.1.0
git commit -am "chore(release): v1.1.0"
# 3. Tag (signed if you have a signing key: git tag -s) and push
git tag -a v1.1.0 -m "v1.1.0"
git push origin main v1.1.0
```

Watch the run under **Actions > Release**; the release appears under
**Releases** when it finishes. Pre-releases: tag `v1.1.0-rc.1` (marked
pre-release automatically).

Local dry run of the artifacts: `make dist` (needs a clean, committed tree).

### If a release fails

- Workflow failed before publishing: fix on `main`, then move the tag:
  `git tag -d v1.1.0 && git push origin :refs/tags/v1.1.0`, re-tag, push.
- Never re-use a version that was already published; release `v1.1.1` instead.

## 4. Users verify downloads

```sh
v=1.1.0
curl -fsSLO https://github.com/your-github-name/git-attribution-guard/releases/download/v$v/git-attribution-guard-$v.tar.gz
curl -fsSLO https://github.com/your-github-name/git-attribution-guard/releases/download/v$v/SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS      # macOS: shasum -a 256 -c --ignore-missing SHA256SUMS
tar xzf git-attribution-guard-$v.tar.gz && sh git-attribution-guard-$v/install.sh
```

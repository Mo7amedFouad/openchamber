---
name: daily-upstream-sync
schedule: "0 3 * * *"
enabled: true
model: meta/muse-spark
agent: build
timezone: Africa/Cairo
---
Goal: Merge latest openchamber/openchamber:main into Mo7amedFouad/openchamber:main, FIXING any merge conflicts, and push to origin/main to trigger Docker image build. DONE = origin/main contains all upstream commits, working tree clean, push succeeded, no unresolved conflicts.

STEPS (use git+gh CLI only, no full clone):

1. Verify: `git status --porcelain` must be clean; `git branch --show-current` == main.
2. `git remote get-url upstream || git remote add upstream https://github.com/openchamber/openchamber.git`
3. `git fetch upstream main --prune`
4. `ahead=$(git rev-list --count origin/main..upstream/main); echo "ahead:$ahead"` - if 0 -> DONE (already up-to-date, exit).
5. `git checkout main && git pull --ff-only origin main`
6. Try merge: `git merge upstream/main --no-edit --no-ff`
   IF CONFLICT (exit !=0):
     a. List: `git diff --name-only --diff-filter=U` and `git status`
     b. For EACH conflicted file:
        - Read upstream version: `git show :2:<file>` and fork version `git show :3:<file>` and base `git show :1:<file>`
        - Understand intent: Keep fork-specific customizations (Dockerfile: extra apt tools, pip --ignore-installed, --break-system-packages, playwright, etc. - see Dockerfile:89,134) while applying upstream fixes (base image bumps, security patches, workflow fixes).
        - For Dockerfile: Start from upstream's Dockerfile content, then re-apply fork's additions (extra apt packages: bat, ffmpeg, chromium, python deps; pip lines with --ignore-installed). Do NOT revert to upstream minimal file. Ensure syntax valid.
        - For .github/workflows/docker.yml: keep fork's multi-arch matrix (linux/amd64+arm64) but apply upstream's label/cache fixes.
        - For package.json/bun.lock: prefer upstream if only version bump, but keep patches/ if fork has custom.
        - Edit file to resolve, `git add <file>`.
     c. After all files staged: `git status` must show no U. `git merge --continue` or `git commit --no-edit`.
     d. Verify merge: `git log --oneline -3` shows merge commit, `git diff HEAD~1 --stat` sane.
7. Validate (lightweight): `git diff --check` no whitespace errors; `dockerfile_lint` if available; `bun run build:web --help` or `tsc --noEmit` quick check if changed TS files.
8. Push: `git push origin main` - if rejected (non-ff), `git pull --rebase origin main` then push. Use gh auth (`gh auth status`).
9. Post-push: `gh run list --repo Mo7amedFouad/openchamber --limit 1` -> wait 12m then `gh run view --log-failed` on docker workflow; if failed due to known packaging issue, ensure Dockerfile still has `--ignore-installed`.

Rules: FIX conflicts, do NOT abort or --abort. Prefer keeping fork's intentional divergences (Dockerfile extra tooling). If conflict is unresolvable after 2 attempts, create branch `merge/upstream-$(date +%Y%m%d)` and push there + `gh pr create`, then BLOCKED. Use --no-ff merge commits for traceability.

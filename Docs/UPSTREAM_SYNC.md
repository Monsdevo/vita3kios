# Upstream synchronization

`External/Vita3K` is a Git submodule pinned by the parent repository. The parent
commit is the reproducible source of truth.

Planned remotes inside a developer clone:

- `origin`: official `https://github.com/Vita3K/Vita3K.git` until a vita3kios fork
  exists; later the fork becomes `origin`.
- `upstream`: always the official Vita3K repository after a fork exists.

Update procedure:

1. Confirm the current parent and submodule worktrees are clean.
2. Fetch official upstream without moving the parent pin.
3. Build/test the old pin and store the baseline.
4. Select one explicit upstream commit; never track a floating branch in release.
5. Rebase or replay small iOS commits and resolve conflicts by topic.
6. Run macOS, iOS compile, device JIT/GPU and regression tests.
7. Update the parent submodule pointer and `ROADMAP.txt` change record together.

Generated source copies and bulk upstream file duplication are not accepted.

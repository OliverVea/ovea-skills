---
name: ovea-workstyle
description: How a piece of work flows in Oliver's repos — branch off main into a new Orca worktree, let an agent iterate there, then squash, rebase onto main and push to main. Use when starting a task, feature or fix in one of his repos, when handing work to an agent, and before committing, merging or pushing finished work.
allowed-tools: Bash Read
---

# Workstyle

One piece of work, one worktree. History on `main` stays linear.

## Start

1. Fetch, then branch off an up-to-date `origin/main` into a new Orca worktree:
   `orca worktree create --repo path:<repo> --name <short-name> --base-branch origin/main`
   (load the `orca-cli` skill for the details, e.g. launching an agent in it with `--agent`).
2. Work only in that worktree. The main checkout stays clean on `main`: no edits, no uncommitted
   changes, no other branch checked out. Other sessions branch from it. If it is dirty, say so
   instead of working around it.

## Iterate

- The agent iterates in the worktree, committing as it goes.
- The repo's `CLAUDE.md` rules apply there as everywhere (its gate, its decision rules).

## Finish

1. Squash commits that do the same thing (a fix-up, a review answer, the docs for a change), so each
   change is one commit.
2. Run the repo's gate (`tools/check.sh`, or what its `CLAUDE.md` names).
3. `git fetch origin && git rebase origin/main`, re-run the gate if the rebase brought changes, then
   `git push origin HEAD:main`. No merge commits; pushed history is never rewritten.
4. When a push deploys, name the run that carries it (`pl wait push "<pipeline>" <sha>`).
5. Remove the worktree and its branch: `orca worktree rm --worktree path:<path> --delete-branch`.

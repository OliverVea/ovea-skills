---
name: ovea-workstyle
description: How a piece of work flows in all of Oliver's repos, on every machine — branch off main into a new worktree, let an agent iterate there, squash and rebase, then publish the way the repo's CLAUDE.md says (push to main, or a PR merged after CI) or, when it doesn't say, ask Oliver whether to merge it yourself or let him review all or part of it. Use when starting a task, feature or fix in one of his repos, when handing work to an agent, and before committing, pushing, opening a PR or merging finished work.
allowed-tools: Bash Read AskUserQuestion
---

# Workstyle

One piece of work, one worktree. History on `main` stays linear. Nothing reaches `main` unless the
repo allows it or Oliver said so for this change.

## Start

1. Fetch, then branch off an up-to-date `origin/main` into a new worktree. Use Orca where it is
   installed:
   `orca worktree create --repo path:<repo> --name <short-name> --base-branch origin/main`
   (load the `orca-cli` skill for the details, e.g. launching an agent in it with `--agent`).
   Without Orca, run `git worktree add -b <short-name> ../<repo>-<short-name> origin/main`.
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
3. `git fetch origin && git rebase origin/main`, and re-run the gate if the rebase brought changes.
4. Publish (below).
5. When a merge deploys, name the run that carries it (`pl wait push "<pipeline>" <sha>`).
6. Remove the worktree and its branch: `orca worktree rm --worktree path:<path> --delete-branch`,
   or `git worktree remove <path> && git branch -D <short-name>` without Orca.

## Publish

### Does the repo say?

Read the repo's `CLAUDE.md` (and any nested one covering the changed files) for a publishing
policy: which changes need Oliver's review in a PR, and which an agent may land itself. For example:

```markdown
## Publishing

- Agents may land docs, tests and generator changes themselves.
- Public API changes and anything under `.github/workflows/` go in a PR for Oliver's review.
```

- If the policy covers this change, follow it without asking.
- If there is no policy, or it doesn't cover this change, ask (next section). Most repos won't
  have one.

An earlier approval doesn't carry over: "merge it yourself" covers the change it was given for, not
the next one. Only a policy written in the repo is standing permission. Notes in memory don't
count either. If Oliver wants something permanent, offer to add it to the repo's `CLAUDE.md`.

### Ask

When the work is ready to publish, use AskUserQuestion. The question must make sense on its own:
name the change in one line and say the gate passed. Offer these options:

1. **Merge it yourself.** Land it as in *Landing it* below.
2. **I'll review it.** Open a PR (*Opening a PR*), give the link and stop. Merge only when Oliver
   says to, or when it is approved and he asked you to merge on approval.
3. **Review a specific part.** Ask a follow-up AskUserQuestion: which part?
   - Put a table of what the change involves in the question: one row per part (an area or concern,
     not every file), with its files, what changed, and the size (`+/-` lines).

     | Part | Files | What changed | Size |
     |---|---|---|---|
     | Generator | `generator/Api.cs` | Emits `TryX(out ...)` for fallible calls | +80/-12 |
     | Generated output | `src/.../Generated/*` | Regenerated | +900/-300 |
     | Tests | `tests/...` | One flow test for the new overloads | +60 |

   - Make the parts the options, with `multiSelect: true`. With more than four parts, group the
     small ones, since there are at most four options.
   - Open the PR and point Oliver at the chosen parts (files, and line ranges where they help), or
     walk him through them in the session if he'd rather. Land the change once he's happy with
     those parts. He has delegated the rest, so don't ask again about it.

### Landing it

- **Direct push allowed** (no branch protection on `main`): `git push origin HEAD:main`.
- **PRs required:** open a PR, wait for CI (`gh pr checks <n> --watch`), then squash-merge it. If CI
  fails, fix it, push the fix to the branch and wait again. Don't merge a red PR.
- No merge commits, and never rewrite history that has been pushed to `main`.

### Opening a PR

Push the branch and open a PR with a title like the commit message and a body saying what changed
and why. If the change was split, link the PRs. To act on review comments as they arrive, use the
`ovea-watch-prs` skill.

---
name: ovea-workstyle
description: How a piece of work flows in all of Oliver's repos, on every machine — branch off main into a new worktree, let an agent iterate there, squash and rebase, then publish the way the repo's CLAUDE.md says (push to main, or a PR with auto-merge) or, when it doesn't say, ask Oliver whether to merge it yourself or let him review all or part of it; a PR lands through auto-merge, watched until it merges. Use when starting a task, feature or fix in one of his repos, when handing work to an agent, and before committing, pushing, opening a PR or merging finished work.
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
6. Once the change is on `main` (not before: a stuck PR is fixed from it), remove the worktree and
   its branch: `orca worktree rm --worktree path:<path> --delete-branch`, or
   `git worktree remove <path> && git branch -D <short-name>` without Orca.

## Publish

### Does the repo say?

Read the repo's `CLAUDE.md` (and any nested one covering the changed files) for a publishing
policy: which changes need Oliver's review in a PR, and which an agent may land itself. For example:

```markdown
## Publishing

- Agents land their own changes without review: push to `main`.
- **A spec change needs the owner's approval of the spec alone** before the code behind it is built.
- Changes to `src/Core/` go in a PR for the owner's review.
```

- If the policy covers this change, follow it without asking.
- If there is no policy, or it doesn't cover this change, ask (next section).

Policies live in the repo's `CLAUDE.md`, never in memory. An earlier approval doesn't carry over:
"merge it yourself" covers the change it was given for, not the next one. If memory holds a
publishing rule for a repo, point it out and offer to move it into the repo's `CLAUDE.md`.

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

Then ask a second AskUserQuestion: should this choice become the repo's policy? Offer to add a
`## Publishing` section to its `CLAUDE.md`, worded for this kind of change (e.g. "docs and tests:
agents push", or "changes to `src/Core/` go in a PR for review"), or to leave it as a one-off. Write
the policy only on a yes, and land it with the change or as its own commit.

### Landing it

- **The policy says push to `main`** (and GitHub doesn't require a PR): `git push origin HEAD:main`.
- **Otherwise, a PR with auto-merge.** Open the PR (*Opening a PR*) and turn on auto-merge right
  away: `gh pr merge <n> --auto --rebase` (`--squash` where rebase is off). Auto-merge means "merge
  when it's green": GitHub, or the repo's merge queue, lands it once the required checks pass. Then
  watch it (next section). Never use `--admin` or another bypass.
- If GitHub refuses auto-merge (off in the repo settings, or `main` requires no checks), say so,
  wait for the checks (`gh pr checks <n> --watch`, or the repo's gate when GitHub runs none) and
  merge it yourself. Don't merge a red PR.
- Auto-merge is the same decision as merging: turn it on only when the policy or Oliver lets you
  land the change. A PR waiting for his review gets it only once he approves.
- No merge commits, and never rewrite history that has been pushed to `main`.

### Watching a PR until it lands

After turning on auto-merge, watch the PR with the `ovea-watch-prs` skill (Monitor, re-armed when it
expires) until it is merged or closed, for at most 12 hours. Its "don't push in response" rule doesn't
apply here: landing this PR is your task. When it is stuck, fix it:

- **A check failed, or the merge queue removed it:** fix it in the worktree, push to the branch.
  Auto-merge stays on, and an Olve.Pipelines merge queue takes the new head again by itself.
- **Conflicts with `main`:** `git fetch origin && git rebase origin/main`, re-run the gate,
  `git push --force-with-lease`.
- **A review comment or a question:** answer it, or fix what it asks for.
- **Something you can't fix** (a broken runner, an outage, a decision for Oliver): say so and leave
  it.

Don't wait for the merge. If there is more work, carry on with it while the watcher runs. If there
isn't, stop and let its notifications wake you. After 12 hours without a merge, stop watching and
report where the PR is.

### Opening a PR

Push the branch and open a PR with a title like the commit message and a body saying what changed
and why. If the change was split, link the PRs. To act on review comments as they arrive, use the
`ovea-watch-prs` skill.

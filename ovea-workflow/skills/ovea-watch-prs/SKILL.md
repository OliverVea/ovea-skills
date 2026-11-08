---
name: ovea-watch-prs
description: Subscribe to activity on one or more GitHub pull requests (comments, inline review comments, reviews, your own unsubmitted draft comments, pushes, state changes, CI checks) and get notified in-session as it happens. Use when the user says "watch/subscribe to/monitor/keep an eye on PR …", "tell me when someone comments on …", or wants to react to review feedback as it arrives.
---

# Watch PRs

`${CLAUDE_SKILL_DIR}/watch-prs.sh` polls PRs with `gh` and prints **one line per new or changed item**. Run it under the **Monitor** tool so each line arrives as a notification.

Needs `bash`, `jq` and a signed-in `gh` (recent enough for `gh pr checks --json`). If a poll fails on every attempt, run the one-shot check below in a shell to see the error.

## Start a subscription

1. Resolve the PRs. Accepted forms: full URL, `owner/repo#N`, or bare `N` (repo of the cwd).
2. Load Monitor if deferred (`ToolSearch select:Monitor`), then start it:

```
Monitor(
  command: "bash '${CLAUDE_SKILL_DIR}/watch-prs.sh' --interval 60 --state-dir <scratchpad>/watch-prs OliverVea/Olve.Trains#34 https://github.com/o/r/pull/7",
  description: "PR activity: Olve.Trains#34, o/r#7",
  timeout_ms: 1800000
)
```

3. **Always pass `--state-dir` set to this session's scratchpad** (or another dir only you use). Seen-state is per directory. Two watchers sharing a dir steal each other's events, and nobody gets an error. The `~/.cache/watch-prs` default is only for manual CLI use.
4. The first poll prints `watching (baseline: N existing items)` per PR. Existing activity is recorded silently. Pass `--replay` to emit it instead, e.g. when the user wants to catch up on what is already there.
5. Monitors expire after at most 30 minutes. **On expiry, re-arm with the same command and the same `--state-dir`.** Nothing repeats and nothing in between is lost. Stop re-arming when the user says so, or when every watched PR is merged or closed.

The user's own comments and reviews are skipped (they wrote them). Pass `--include-self` to include them. The user's own drafts are always shown.

For a one-shot check without subscribing, use `bash '${CLAUDE_SKILL_DIR}/watch-prs.sh' --once PR...`.

## What it reports

| Line | Source |
|---|---|
| `comment by X` | conversation comments |
| `review-comment by X on path:line` | inline review comments (incl. replies) |
| `review APPROVED/CHANGES_REQUESTED/COMMENTED by X` | submitted reviews (empty-body COMMENTED reviews are skipped since their inline comments are reported) |
| `DRAFT comment (yours, unsubmitted)` | comments in **your own** pending review |
| `draft N no longer pending` | your draft was submitted or deleted |
| `(edited) …` | any comment or review body changed |
| `state=… draft=… review=…` | open/closed/merged, draft flag, review decision |
| `new head commit` | a push to the PR branch |
| `check NAME: pass/fail/…` | CI checks that finished |
| `poll failed (will retry)` | gh/network error. Repeated failures mean auth or a bad PR spec. |

**Limitations:** A review edit that keeps the body the same length goes unnoticed, because review edits are detected by body length. GitHub only exposes pending (draft) reviews to their author. You can see the authenticated user's drafts, but never other people's drafts.

## When events arrive

Summarise them briefly for the user. Bodies are truncated to 300 characters, so fetch the full thread (`gh api` on the URL in the line) before acting on one. Don't reply on GitHub or push changes in response unless the user has asked you to.

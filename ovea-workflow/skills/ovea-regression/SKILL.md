---
name: ovea-regression
description: How an agent works with Olve.Regression (formerly Olve.VisualRegression, VR), Oliver's screenshot baseline, diff and approval service — the `reg` CLI, preview runs to check a UI change against the baselines, waiting for a review, and the pipeline step that gates a deploy on it. Use when the user names Olve.Regression, Olve.VisualRegression, VR, screenshot baselines or a visual review, when a repo's pipeline has a `visual-review` step or runs `reg`, before running any `reg` command, or when a change alters what an app's screenshots look like. Not for unit-test snapshots or other tools' visual testing (Percy, Chromatic, Playwright's toHaveScreenshot).
allowed-tools: Bash Read
---

# Olve.Regression — agent playbook

Regression stores each project's screenshot baselines (with their history), compares new screenshots with
them, and lets the owner approve or reject the differences, on a phone-first web UI. A consumer's
pipeline gates on it: Olve.Trains' `visual-review` step submits the integration suite's screenshots and
waits for the verdict before it publishes.

## Instances

| Instance | URL (Tailscale) | Profile convention |
|---|---|---|
| prod | `https://reg-private.ovea.pro` | `default` |
| beta | `https://reg-beta.ovea.pro` | `beta` |

The review UI is at each URL; a run's review is `<url>/runs/<id>`.

## Concepts

- **Project** (`trains`): a registered key and name. **Baseline**: one per project, platform and name
  (`trains/linux/burger-menu`, the PNG's file name without `.png`); there are no branch baselines.
- **Pass rule** (Regression's constant, not configurable): a pixel counts as changed when a channel differs by
  more than 2, and a screenshot passes when at most 5 in 1000 pixels changed. New screenshots (no
  baseline) and missing ones (a baseline the run lacks) always need review.
- **Pipeline run**: one open per project and platform; approved, it moves the baselines; Regression posts its
  verdict to the step's callback URL. **Preview run** (the default of `reg submit`): reviewed the same
  way, never moves a baseline, several may be open, no callback.
- A run with no differences passes at once, with no review. Otherwise the owner decides each change
  and finishes the review; a rejection needs a comment. A screenshot approved earlier with identical
  pixels against the same baseline version starts **pre-approved**, but the owner still finishes the
  review.

## Rules

1. **Use the `reg` CLI**, not curl or the API. `reg --help`, `reg <command> --help`, `--json` for machine
   output. If `reg` is missing or old, install the build the instance serves:
   `curl -fsSL https://reg-private.ovea.pro/install.sh | sh` (Windows: `irm …/install.ps1 | iex`), or
   `reg update`.
2. **The user logs in, not you.** Check `reg profile list`; if the profile isn't logged in, ask the user
   to run `! reg login --device` (beta: `! reg login --device --profile beta --api-url https://reg-beta.ovea.pro`).
   Never handle tokens.
3. **Never review for the owner.** Don't run `reg review approve|reject|approve-all|finish` unless the
   user tells you the decision for that run. Report the review link and what changed instead.
4. **Check a UI change with a preview** before pushing it, when the repo produces screenshots: run its
   screenshot suite, then `reg submit <project> <png…> --platform <p> --commit <sha>` (a preview) prints
   the review link. Tell the user. A preview the owner approves pre-approves the same pixels in the
   next pipeline run, so the push's review is quicker. `--wait` (or `reg wait <run>`, run in the
   background) waits for the review: exit 0 passed or approved, 1 rejected (the comments are printed:
   act on them), 3 cancelled, 124 timeout.
5. **A rejected pipeline review fails the step** with the reviewer's comments; nothing after it
   runs. Read them with `reg run get <run>` (or the failed step's note in `pl run get`), fix what they
   say, and push; the next run is reviewed again.
6. **Destructive commands need the user's go-ahead**: `reg project delete` removes a project's runs,
   baselines and remembered approvals; `reg run cancel` cancels a review without calling back.

## The pipeline step

A consumer gates on Regression with one Olve.Pipelines step (SDK 2.0.0-beta.35 or later; load the
`ovea-olve-pipelines` skill before changing `.pipelines/`). Its preflight submits a pipeline run with
the step's callback URL and links the review; the step then waits for Regression's verdict with no pod up:

```ts
const review = step({
  name: "visual-review",
  description: "…",
  image: "debian:stable-slim",
  input: {
    source: Source,
    screenshots: M.Screenshots,
    verdict: external(M.Verdict, { title: "Screenshots approved in Olve.Regression?", from: [callback()] }),
  },
  secrets: [REG_TOKEN],
});
export const visualReview = implement(review, ({ verdict }) => {
  if (!verdict.accepted) throw new Error("The screenshots were not accepted");
}, {
  preflight: async ({ source, screenshots }, ctx) => {
    // install reg from REG_URL, then:
    // reg submit <project> <dir>/*.png --platform … --commit <sha> --pipeline --supersede \
    //   --source-url <the run's page> --callback-url ctx.inputUrl(review, "verdict") --json
    ctx.link(reviewUrl, "Review in Olve.Regression");
  },
});
```

- `--supersede` cancels the platform's open pipeline run (an older build's) first; without it a second
  one gets 409. Regression answers `{"accepted":true}` or a decline carrying the rejection comments.
- The step needs a machine token: Regression's chart configures `Auth:Tokens:<name>` as the sha256 of an
  `olreg_…` token (prod in `values.yaml`, beta in `values-beta.yaml`), and the consumer's pipeline holds
  the token as a secret (`pl secret set`, value from stdin). The project must be registered first
  (`reg project add <key> --name <name>`, with the user's go-ahead).
- Olve.Trains' `.pipelines/steps/visual-review.ts` is the working example.

## Don't

- Don't approve, reject or finish a review yourself (rule 3).
- Don't commit baselines or screenshots to the consumer's repo; Regression owns them.
- Don't poll with `sleep` loops; use `reg wait` or `reg submit --wait`.
- Don't answer usage questions from memory; read `reg <command> --help`.

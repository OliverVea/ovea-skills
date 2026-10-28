---
name: ovea-olve-pipelines
description: How an agent works with Olve.Pipelines, Oliver's homelab GitOps CD service — driving it with the `pl` CLI, waiting for deploys, profiles and login, changing a pipeline safely. Use when the repo has `.pipelines/pipeline.ts`, when the user names Olve.Pipelines, or before running any `pl` command. For a generic "pipeline" / "deploy" / "CI" request, check the repo for `.pipelines/` first. Without it (GitHub Actions in `.github/workflows/`, a data pipeline, a Claude Code workflow) this skill does not apply. Points to the instance's /docs for reference; this skill is the agent playbook.
---

# Olve.Pipelines — agent playbook

Olve.Pipelines builds and deploys Oliver's repos: each step runs as a Kubernetes Job, defined in
the repo it deploys. This skill is **how to act**; the reference (SDK, triggers, steps, runs,
troubleshooting) is served by each instance at **`/docs`** (agent index: `/llms.txt`). Read those
instead of guessing or reading the service source.

## Recognize it

A repo's pipeline is **`.pipelines/pipeline.ts`** (with `handlers/`, `models.ts`, a `package.json`):
a typed TypeScript pipeline on the SDK `@olivervea/pipelines`.

In Oliver's repos "pipeline" means an Olve.Pipelines pipeline, not GitHub Actions.

## Instances

| Instance | URL (Tailscale) | Profile convention |
|---|---|---|
| prod | `https://pipelines-private.ovea.pro` | `default` |
| beta | `https://pipelines-beta.ovea.pro` | `beta` |

The web UI is at each URL.

## Rules

1. **Use the `pl` CLI for everything.** Not `curl`, not the HTTP API, not `kubectl`: `pl` handles
   auth, naming (pipelines by name, runs as `<pipeline>#<run>`, steps as `#<run>/<step>`) and the
   API's details. `pl help`, `pl <noun> --help`. If `pl` is missing or `pl wait` / `pl profile`
   are unknown commands (an old `pl`), install the current one from prod, which serves
   the `pl` it was deployed with:
   ```sh
   curl -fsSL https://pipelines-private.ovea.pro/install.sh | sh        # Linux → ~/.local/bin/pl
   irm https://pipelines-private.ovea.pro/install.ps1 | iex             # Windows
   pl --version && pl profile list                                         # then rule 2 if not logged in
   ```
   It replaces `~/.local/bin/pl`.
2. **The user logs in, not you.** Login is interactive OIDC against the instance's own Dex
   (`<instance>/dex`, which sends the user on to GitHub; only allow-listed accounts get in): a
   browser flow by default, or with `--device` a device flow that prints a URL (and QR code) to
   approve. There are no machine tokens. Never handle tokens.
   Everything on prod needs a session, reads included (beta allows anonymous reads). Check
   `pl profile list`, and if the profile isn't logged in, ask the user to run it with the `!`
   prefix and `--device` so the link lands in the session:
   `! pl login --device --api-url https://pipelines-private.ovea.pro` and
   `! pl login --device --profile beta --api-url https://pipelines-beta.ovea.pro`.
   Tokens refresh themselves; expect to ask again only when a refresh fails.
3. **Pick the instance with a profile.** `--profile <name>` goes **after** the command
   (`pl pipeline list --profile beta`), or set `PIPELINES_PROFILE` for a shell. No flag means
   `default`. Don't edit `~/.pl`.
4. **Wait with `pl wait`, never with hand-rolled poll loops.** It re-checks on the instance's live
   events, exits 0 (succeeded), 1 (failed or can no longer happen), 2 (usage error), 3 (a step
   waits for a person's input: tell the user, with the address it printed; callback and poll
   inputs answer themselves and don't stop the wait) or 124 (`--timeout`), prints the result on stdout and progress on stderr. A superseded run is followed
   to the run that superseded it (`--no-follow` to stop there). Run it as a background task and act on the exit
   code:
   ```sh
   pl wait push "<pipeline>" <sha> --until finished --timeout 60m   # the run of a pushed commit
   addr=$(pl wait push "<pipeline>" <sha>)                          # just its address
   pl wait run "<pipeline>#<run>/<step>" --timeout 30m              # one step
   pl wait reconcile "<pipeline>" <sha>                             # a pipeline-definition commit applied
   ```
5. **Know what a push does before you push.** The pipeline's `onPush` in `.pipelines/pipeline.ts`
   decides it (e.g. some pipelines deploy beta, smoke-test, then **prod** on every push). Runs
   flow on concurrently: an older run keeps going while newer ones build behind it; only where two
   runs' attempts of the same step are both waiting does the newer win (the older run is then
   `Superseded`). Still batch related commits rather than pushing one by one.
6. **Confirm before prod-affecting actions** (`pl trigger` with a prod input, `pl run continue`
   to promote, `pl step unblock`, `pl pipeline switch`, deleting secrets or pipelines) unless the
   user asked for exactly that.
7. **Changing a pipeline** = edit `.pipelines/` and push; the shape is git-owned (no API changes
   it). Before pushing: `pl dev describe` (and `pl dev validate`) in the repo; `pl dev` needs Bun and
   runs the SDK the pipeline's `package.json` pins, so `bun install` in `.pipelines/` first. Every step needs a
   `description` (may be `""`). Use a library step (`steps.*`) where one fits; a step only this
   pipeline needs is a custom step with a `handlers/` file; one several repos need is a reusable
   step (`/docs/pipeline-reference.md#reusable-steps`), not a copy. After pushing, `pl wait reconcile` the commit; a failed reconcile
   holds all runs of the pipeline until fixed, and shows in `pl binding status <pipeline>`.
   Reconcile checks the pipeline with the server code the instance is running, so a pipeline can't
   use an SDK feature that needs a newer server than the instance has. For Olve.Pipelines itself:
   **push the server change on its own, let it reach prod, then push the pipeline change that
   needs it.** If a reconcile is already stuck that way, deploy the commit with the active
   version (`pl trigger "<pipeline>" --field sha=<sha> …`, a prod action: confirm first), then
   `pl binding reconcile "<pipeline>"`. After a server change in how manifests are read (a new
   manifest field, a validator rule), `pl binding reconcile "<pipeline>" --rebuild` reconciles the
   applied commit again; the version changes only if the manifest does.
8. **Report the run with every change.** When you tell the user about a change that a push
   deploys, name the run that carries it and where it is: `pl wait push "<pipeline>" <sha>` prints
   `<pipeline>#<run>`; say e.g. "`Olve.Pipelines v2#36` (running)" or "#36, green through prod".
   A newer push's run may be the one that carries your commit; say which.

## Reading state

```sh
pl pipeline list                               # health, last run, active version, blocked steps
pl run list "<pipeline>"                       # newest first
pl run get "<pipeline>#<run>"                  # stages, each step's status and reason
pl step logs "<pipeline>#<run>/<step>"         # the real error; --follow while running
pl step output "<pipeline>#<run>/<step>"       # typed output; pl step files / pl step file
pl binding status "<pipeline>"                 # reconcile result, problems, warnings
pl attempts                                    # what's running across pipelines
pl run critical-path "<pipeline>" [--since-version V | --from N --to M] [--step X]   # where the time goes
```

Add `--json` for machine-readable output. A step shown as `excluded` wasn't part of that run (its
`when` didn't match); `skipped` means it was skipped (handler or a missing input).

## Acting

- **Deploy** = push to the bound branch (rule 5), or `pl trigger "<pipeline>" --field k=v`.
- **Promote / change input of a finished run**: `pl run continue "<pipeline>#<run>" --field
  deployTo=prod` keeps completed stages and runs the rest.
- **Retry a step**: `pl step rerun "<pipeline>#<run>/<step>" --continue`.
- **Stop**: `pl step cancel …` / `pl run cancel …`.
- **A step waiting for external input** (`pl input list`): never answer or decline it yourself
  (`pl input answer|decline`) unless the user tells you the answer for that step; report the
  address and what it asks.
- **Block a step** (`pl step block|unblock "<pipeline>/<step>"`, `pl step blocked "<pipeline>"`):
  holds every run that reaches it. Only while working on the pipeline or its target, or in an
  incident, and only when the user asks; unblock when done. Never use it as an approval step, and
  don't unblock a step someone else blocked without asking. ("Gate" means a step that decides
  whether a run goes on: tests, visual regression.) Never add a manual promotion or approval step
  to a pipeline: pushes flow on their own.
- **Secrets**: `pl secret list "<pipeline>"`; set values from stdin or `--from-env` (never put a
  value on the command line or in output). Deleting a secret the config references needs `--force`
  and holds new runs until it's set again; confirm first.
- **Config** (the per-instance values a pipeline declares with `config(...)`: targets, auth, …):
  `pl config get "<pipeline>" > app.yml`, edit, `pl config set "<pipeline>" -f app.yml`;
  `pl config history|rollback|check`. Every save is a new numbered snapshot (`config #N`) validated
  against the schema. Config is readable; anything sensitive is a secret it references
  (`{ secret: NAME }`). Changing config that targets prod is a prod-affecting action (rule 6).
- **Deploy targets are config**: where a pipeline using `deployTarget()` / `helmTarget()` deploys
  is `target.<stage>.kind` in its config: `inCluster` or `ssh` (helm), `compose` (a Docker Compose
  deployer, `/docs/compose-deploy.md`) or `none` (not deployed). Changing it is a config change
  (`pl config set`, then a new run), not a pipeline change.
- **Pending / held versions**: a new version whose config or referenced secrets aren't satisfied
  stays **pending** (the active one keeps running; pushes wait). `pl binding status` names what's
  missing; set it and the version activates by itself. Don't work around it with `pl pipeline switch`.
- **Runs pin their config** like their version (`pl run get` shows `vN, config #M`): `run continue`
  and `step rerun` reuse it; picking up new config needs a new run.

## Don't

- Don't treat `.pipelines/` as example config — it's live deployment config.
- Don't poll with `sleep` loops, `curl` or `watch`; use `pl wait`.
- Don't log in for the user, copy tokens, or edit `~/.pl`.
- Don't answer usage questions from memory or the service source; read the instance's `/docs`.

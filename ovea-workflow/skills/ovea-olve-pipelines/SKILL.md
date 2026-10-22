---
name: ovea-olve-pipelines
description: How an agent works with Olve.Pipelines, Oliver's homelab GitOps CD service — recognizing a pipeline, driving it with the `pl` CLI, waiting for deploys, profiles and login, changing a pipeline safely. Use when a repo contains a `.pipelines/` directory, when the user says "pipeline" / "deploy" in a homelab context, or before running any `pl` command. Points to the instance's /docs for reference; this skill is the agent playbook.
---

# Olve.Pipelines — agent playbook

Olve.Pipelines builds and deploys Oliver's repos: each step runs as a Kubernetes Job, defined in
the repo it deploys. This skill is **how to act**; the reference (SDK, triggers, steps, runs,
troubleshooting) is served by each instance at **`/docs`** (agent index: `/llms.txt`). Read those
instead of guessing or reading the service source.

## Recognize the version

- **`.pipelines/pipeline.ts`** (with `handlers/`, `models.ts`, a `package.json`) → **v2**: a typed
  TypeScript pipeline on the SDK `@olve/pipelines`. This is the current system.
- **`.pipelines/config.yaml`** → **v1** (legacy, still deploying repos not yet migrated). v1 has its
  own `pl` binary and API; don't apply v2 commands or concepts to it.

In Oliver's repos "pipeline" means an Olve.Pipelines pipeline, not GitHub Actions.

## Instances

| Instance | URL (Tailscale) | Profile convention |
|---|---|---|
| v2 prod | `https://pipelines-v2-private.ovea.pro` | `default` |
| v2 beta | `https://pipelines-v2-beta.ovea.pro` | `beta` |

The web UI is at each URL. Everything below assumes v2.

## Rules

1. **Use the `pl` CLI for everything.** Not `curl`, not the HTTP API, not `kubectl`: `pl` handles
   auth, naming (pipelines by name, runs as `<pipeline>#<run>`, steps as `#<run>/<step>`) and the
   API's details. `pl help`, `pl <noun> --help`. If `pl` is missing or `pl wait` / `pl profile`
   are unknown commands (an old or v1 `pl`), install the current one from v2 prod, which serves
   the `pl` it was deployed with:
   ```sh
   curl -fsSL https://pipelines-v2-private.ovea.pro/install.sh | sh        # Linux → ~/.local/bin/pl
   irm https://pipelines-v2-private.ovea.pro/install.ps1 | iex             # Windows
   pl --version && pl profile list                                         # then rule 2 if not logged in
   ```
   It replaces `~/.local/bin/pl`; on a machine that still needs v1's `pl`, keep a copy under another
   name first (e.g. `pl-v1`).
2. **The user logs in, not you.** Login is an interactive OIDC device flow. Never handle tokens.
   If a command needs auth (mutations, secrets, step files), check `pl profile list`, and if the
   profile isn't logged in, ask the user to run it with the `!` prefix so the link lands in the
   session:
   `! pl login --api-url https://pipelines-v2-private.ovea.pro` and
   `! pl login --profile beta --api-url https://pipelines-v2-beta.ovea.pro`.
   Tokens refresh themselves; expect to ask again only when a refresh fails.
3. **Pick the instance with a profile.** `--profile <name>` goes **after** the command
   (`pl pipeline list --profile beta`), or set `PIPELINES_PROFILE` for a shell. No flag means
   `default`. Don't edit `~/.pl`.
4. **Wait with `pl wait`, never with hand-rolled poll loops.** It re-checks on the instance's live
   events, exits 0 (succeeded), 1 (failed or can no longer happen) or 124 (`--timeout`), prints
   the result on stdout and progress on stderr. Run it as a background task and act on the exit
   code:
   ```sh
   pl wait push "<pipeline>" <sha> --until finished --timeout 60m   # the run of a pushed commit
   addr=$(pl wait push "<pipeline>" <sha>)                          # just its address
   pl wait run "<pipeline>#<run>/<step>" --timeout 30m              # one step
   pl wait reconcile "<pipeline>" <sha>                             # a pipeline-definition commit applied
   ```
5. **Know what a push does before you push.** The pipeline's `onPush` in `.pipelines/pipeline.ts`
   decides it (e.g. some pipelines deploy beta, smoke-test, then **prod** on every push). A newer
   push **supersedes** a running automatic run (its unstarted steps never run), so batch commits
   instead of pushing one by one while a deploy is in flight.
6. **Confirm before prod-affecting actions** (`pl trigger` with a prod input, `pl run continue`
   to promote, `pl step unblock`, `pl pipeline switch`, deleting secrets or pipelines) unless the
   user asked for exactly that.
7. **Changing a pipeline** = edit `.pipelines/` and push; the shape is git-owned (no API changes
   it). Before pushing: `pl dev describe` (and `pl dev validate`) in the repo. Every step needs a
   `description` (may be `""`). After pushing, `pl wait reconcile` the commit; a failed reconcile
   holds all runs of the pipeline until fixed, and shows in `pl binding status <pipeline>`.

## Reading state

```sh
pl pipeline list                               # health, last run, active version, blocked steps
pl run list "<pipeline>"                       # newest first
pl run get "<pipeline>#<run>"                  # stages, each step's status and reason
pl step logs "<pipeline>#<run>/<step>"         # the real error; --follow while running
pl step output "<pipeline>#<run>/<step>"       # typed output; pl step files / pl step file
pl binding status "<pipeline>"                 # reconcile result, problems, warnings
pl attempts                                    # what's running across pipelines
```

Add `--json` for machine-readable output. A step shown as `excluded` wasn't part of that run (its
`when` didn't match); `skipped` means it was skipped (handler or a missing input).

## Acting

- **Deploy** = push to the bound branch (rule 5), or `pl trigger "<pipeline>" --field k=v`.
- **Promote / change input of a finished run**: `pl run continue "<pipeline>#<run>" --field
  deployTo=prod` keeps completed stages and runs the rest.
- **Retry a step**: `pl step rerun "<pipeline>#<run>/<step>" --continue`.
- **Stop**: `pl step cancel …` / `pl run cancel …`.
- **Block a step** (`pl step block|unblock "<pipeline>/<step>"`, `pl step blocked "<pipeline>"`):
  holds every run that reaches it. Only while working on the pipeline or its target, or in an
  incident, and only when the user asks; unblock when done. Never use it as an approval step, and
  don't unblock a step someone else blocked without asking. ("Gate" means a step that decides
  whether a run goes on: tests, approval, visual regression.)
- **Secrets**: `pl secret list "<pipeline>"`; set values from stdin or `--from-env` (never put a
  value on the command line or in output).

## Don't

- Don't treat `.pipelines/` as example config — it's live deployment config.
- Don't poll with `sleep` loops, `curl` or `watch`; use `pl wait`.
- Don't log in for the user, copy tokens, or edit `~/.pl`.
- Don't answer usage questions from memory or the service source; read the instance's `/docs`.

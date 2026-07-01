---
name: ovea-olve-pipelines
description: Recognize and work with Olve.Pipelines, Oliver's homelab GitOps CD service. Use when a repo contains a `.pipelines/` directory (the marker that it deploys via Olve.Pipelines), when the user says "pipeline" / "the pipeline" / "deploy" in a homelab context, or when asked how CD/deployment works for one of Oliver's repos. Points to the authoritative docs rather than reimplementing them.
---

# Olve.Pipelines

**Olve.Pipelines** is Oliver's lightweight GitOps CD service for his homelab. It builds and
deploys repos by running their pipeline steps as Kubernetes Jobs.

Repo: <https://github.com/OliverVea/Olve.Pipelines> — the **README is the canonical reference**.
A fuller, agent-friendly setup guide is served by the running instance at **`/docs`** (raw
Markdown, with a subject index).

## The `.pipelines/` marker

If a repo has a **`.pipelines/` directory** (containing `config.yaml`, optionally
`scripts/*.sh`), that repo is deployed via Olve.Pipelines. This is the signal — treat it like
you would a `.github/workflows/` directory for GitHub Actions.

- `.pipelines/config.yaml` is the **single source of truth** for the pipeline's shape.
- A reconcile loop polls the branch head (~5 min); pushing a commit redeploys automatically.
- You never hand-author triggers or run shape-mutating commands — **shape is git-owned**, so to
  change the build/deploy you edit `config.yaml` and push. (Operational actions — manual
  triggers, job cancel, the promotion gate — are driven with the `pl` CLI.)

## When the user says "pipeline"

In Oliver's repos, "pipeline" almost always means an **Olve.Pipelines** pipeline (not GitHub
Actions, not a generic CI concept). React accordingly:

- **"set up a pipeline" / "add CD"** → add a `.pipelines/config.yaml` to the repo, then bind it.
  [`Olve.Template.Api`](https://github.com/OliverVea/Olve.Template.Api/tree/main/.pipelines)
  ships a copy-me starter (Kaniko build + Helm deploy). Bind it with `pl binding create
  <owner/repo> --credentials-secret <key>` (then `pl secret set` its declared secrets); the
  `Olve.Pipelines` repo's `setup-pipeline` skill wraps this as a full bootstrap runbook.
- **"deploy" / "redeploy"** → usually just push to the bound branch; the deploy poll picks it up.
- **questions about config schema, steps, secrets, promotion gates, triggers** → read the
  README / `/docs` rather than guessing. Don't reinvent the model from memory.

## Mental model (one line each)

- **Production steps** run in parallel → produce an ArtifactBundle (`bundle/<step>/`).
- **Processing steps** run sequentially, each receiving the full bundle (e.g. build → deploy).
- **Secrets** are declared by name in `config.yaml`; values live in the pipeline's k8s secret,
  never in the repo. Referenced as `$SECRET:NAME`.
- **Promotion gate** is operational state (block/unblock/re-promote a step), not git config.

## Driving & inspecting a pipeline — use `pl`

**The `pl` CLI is the interface. Use it for everything** — bind, secrets, status, triggers,
inspection. Don't call the HTTP API directly; `pl` wraps it (and handles auth, output, and the
API's rough edges for you). A web UI exists at the instance root
(<https://pipelines-private.ovea.pro>) for point-and-click inspection and the promotion gate.

`pl` is built and served by the instance itself (no GitHub Releases), so install it straight
from the controller:

- Linux: `curl -fsSL https://raw.githubusercontent.com/OliverVea/Olve.Pipelines/main/install.sh | sh`
- Windows: `irm https://raw.githubusercontent.com/OliverVea/Olve.Pipelines/main/install.ps1 | iex`

It defaults to the private instance over Tailscale — if you can reach the instance, you can
install and use it. Read commands need no auth (`pl pipeline list`, `pl job list`,
`pl job logs <id>`, `pl production list`, `pl processing list`, …); for mutating commands run
`pl login` first (browser OIDC, or `--device` over SSH). Bootstrap and GitOps management are
covered too: `pl binding create/get/status/set-credentials/set-trigger/reconcile` to bind a
repo and drive its reconcile, and `pl secret list/set/delete` to manage the pipeline's k8s
secret values — so a bound pipeline can be created and maintained entirely from the CLI.
`pl --help` lists the full surface.

## Inspecting runs & logs (`pl`)

Answer "did my push deploy?", "which step failed?", "why?" with `pl` — no cluster access, and
no auth for these reads (they work against the private instance over Tailscale; add
`--api-url https://pipelines-beta.ovea.pro` to target beta):

- `pl pipeline list` → pipelines with id + name. Find the one you care about (e.g. `questionbank`).
- `pl job list --pipeline <id>` → that pipeline's jobs, newest first. Each shows type
  (production|processing), status (done|failed|running|…), timings, and a failure reason.
- `pl job get <jobId>` → single job detail.
- `pl job logs <jobId>` → that job's console output (the real error tail).
- `pl processing promotions <id>` → per-step promotion-gate state (blocked/open).
- `pl bundle list <id>` → completed production bundles; **empty until a production group fully
  succeeds** (a failed production step ⇒ no bundle ⇒ no deploy).

Add `--json` to any command for machine-readable output. Jobs reference steps by id (a GUID);
map an id to a name by its order in `.pipelines/config.yaml` (`productionSteps`/`processingSteps`
are listed in order). The same step id across multiple jobs = the controller's retry attempts.

Recipe — "confirm why a deploy didn't run":
```sh
pl pipeline list                     # find the pipeline id by name
pl job list --pipeline <id>          # newest first; spot the failed job
pl job logs <failed-job-id>          # read the tail for the real error
```
A failed **production** step blocks **every** processing step (no beta, no prod) — so a red
typecheck/test gate shows up as a failed production job with the processing steps never created.

## Don't

- Don't treat `.pipelines/` as dead/example config — it's live deployment config.
- Don't reach for the HTTP API or hand-rolled `curl`. Use `pl` for every operation — it's the
  supported interface and wraps the API for you.
- Don't try to mutate pipeline shape at all (no `pl` command or API does it) — edit `config.yaml`
  and push.
- Don't deep-dive the Olve.Pipelines source to answer a usage question — start from the README
  and `/docs`.

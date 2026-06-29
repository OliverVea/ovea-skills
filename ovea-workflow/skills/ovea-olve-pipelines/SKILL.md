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
- You never hand-author triggers or call config-mutation APIs — **shape is git-owned**, so to
  change the build/deploy you edit `config.yaml` and push. (Operations like manual triggers,
  job cancel, and the promotion gate are API-allowed.)

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

## Interacting with a pipeline (CLI, API, or UI)

Three ways to drive and inspect pipelines, in order of preference:

1. **`pl` CLI — recommended.** The operator CLI. It's built and served by the instance itself
   (no GitHub Releases), so install it straight from the controller:
   - Linux: `curl -fsSL https://raw.githubusercontent.com/OliverVea/Olve.Pipelines/main/bootstrap.sh | sh`
   - Windows: `irm https://raw.githubusercontent.com/OliverVea/Olve.Pipelines/main/bootstrap.ps1 | iex`

   It defaults to the private instance over Tailscale — if you can reach the instance, you can
   install and use it. Read commands need no auth (`pl pipeline list`, `pl job list`,
   `pl job logs <id>`, `pl production list`, `pl processing list`, …); for mutating commands run
   `pl login` first (browser OIDC, or `--device` over SSH). Bootstrap and GitOps management are
   covered too: `pl binding create/get/status/set-credentials/set-trigger/reconcile` to bind a
   repo and drive its reconcile, and `pl secret list/set/delete` to manage the pipeline's k8s
   secret values — so a bound pipeline can be created and maintained entirely from the CLI.
   `pl --help` lists the full surface.
2. **HTTP API** — for scripting/automation; this is what the CLI wraps. Read endpoints are open
   from Oliver's network (see below); mutations need a bearer token.
3. **Web UI** — the controller serves a SPA at the instance root
   (<https://pipelines-private.ovea.pro>) for point-and-click inspection and the promotion gate.

## Inspecting runs & logs (read-only HTTP API)

The controller serves both a web UI and a JSON API. Use this to answer "did my push
deploy?", "which step failed?", "why?" — without cluster access. (`pl job list` / `pl job logs`
wrap these same endpoints if you prefer the CLI.)

- **Instance:** `https://pipelines-private.ovea.pro` (private host; reachable on Oliver's
  network/Tailscale). Beta controller: `https://pipelines-beta.ovea.pro`. Use `curl -sSk`.
- **Auth:** the read endpoints below are open from Oliver's network — no token needed. The
  OpenAPI doc (`/openapi/v1.json`, `/swagger/v1/swagger.json`) is `401`-gated, so don't rely
  on it to discover routes; use the verified list here.
- **SPA-fallback gotcha:** unknown `/api/*` paths return **HTTP 200 with the SPA's HTML**
  (body starts with `<`), not a 404. Real API responses are JSON — first char `{` or `[`.
  If you get HTML back, the path is wrong, not empty.

Verified endpoints:

- `GET /api/pipelines` → `[{id,name}]`. Look up the pipeline id by name (e.g. `questionbank`).
- `GET /api/jobs?pipelineId={id}` → `{items:[…]}`, newest first. Each job has `type`
  (`production`|`processing`), a `productionStepId`/`processingStepId` (GUID), `status.type`
  (`done`|`failed`|`running`|…), timestamps, a failure `reason`, and a `jobGroupId` (one run).
- `GET /api/jobs/{jobId}` → single job detail.
- `GET /api/jobs/{jobId}/logs` → that job's console output (JSON-encoded string). **This is the
  log endpoint** — `/log`, `/output`, `/console` all fall through to the SPA.
- `GET /api/pipelines/{id}/processing/promotions` → per processing-step `{processingStepId,
  blocked}` (the promotion-gate state).
- `GET /api/pipelines/{id}/artifact-bundles` → completed production bundles; **empty until a
  production group fully succeeds** (a failed production step ⇒ no bundle ⇒ no deploy).

The API does **not** return step *names* — only GUIDs. Map a step id to a name by its order in
`.pipelines/config.yaml` (`productionSteps`/`processingSteps` are listed in order) or by the
log content. Same step id across multiple jobs = the controller's retry/backoff attempts.

Recipe — "confirm why a deploy didn't run":
```
qb=$(curl -sSk $BASE/api/pipelines | jq -r '.[]|select(.name=="questionbank").id')
curl -sSk "$BASE/api/jobs?pipelineId=$qb"            # newest job first; find the failed one
curl -sSk "$BASE/api/jobs/<failed-job-id>/logs"      # read the tail for the real error
```
A failed **production** step blocks **every** processing step (no beta, no prod) — so a red
typecheck/test gate shows up as a failed production job with the processing steps never created.

## Don't

- Don't treat `.pipelines/` as dead/example config — it's live deployment config.
- Don't try to mutate pipeline shape over the API. Edit `config.yaml` and push.
- Don't deep-dive the Olve.Pipelines source to answer a usage question — start from the README
  and `/docs`.

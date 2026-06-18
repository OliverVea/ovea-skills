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
  ships a copy-me starter (Kaniko build + Helm deploy). The `Olve.Pipelines` repo's
  `setup-pipeline` skill bootstraps the bound pipeline.
- **"deploy" / "redeploy"** → usually just push to the bound branch; the deploy poll picks it up.
- **questions about config schema, steps, secrets, promotion gates, triggers** → read the
  README / `/docs` rather than guessing. Don't reinvent the model from memory.

## Mental model (one line each)

- **Production steps** run in parallel → produce an ArtifactBundle (`bundle/<step>/`).
- **Processing steps** run sequentially, each receiving the full bundle (e.g. build → deploy).
- **Secrets** are declared by name in `config.yaml`; values live in the pipeline's k8s secret,
  never in the repo. Referenced as `$SECRET:NAME`.
- **Promotion gate** is operational state (block/unblock/re-promote a step), not git config.

## Don't

- Don't treat `.pipelines/` as dead/example config — it's live deployment config.
- Don't try to mutate pipeline shape over the API. Edit `config.yaml` and push.
- Don't deep-dive the Olve.Pipelines source to answer a usage question — start from the README
  and `/docs`.

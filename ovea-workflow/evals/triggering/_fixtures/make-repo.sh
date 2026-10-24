#!/usr/bin/env bash
# Builds a throwaway git repo in the current directory for one triggering case.
# Usage: make-repo.sh <fixture>   fixture: v2 | gha | claudewf | v2+claudewf | etl
set -euo pipefail
fixture="$1"

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config core.autocrlf false

app() {
  mkdir -p src
  cat > package.json <<'J'
{ "name": "homelab-status", "version": "0.3.0", "private": true,
  "scripts": { "build": "tsc", "lint": "eslint src", "test": "vitest run" } }
J
  cat > src/index.ts <<'J'
import { createServer } from "node:http";
createServer((_, res) => res.end("ok")).listen(8080);
J
  printf '# homelab-status\n\nTiny status page for the homelab.\n' > README.md
}

pipelines_v2() {
  mkdir -p .pipelines/handlers
  cat > .pipelines/package.json <<'J'
{ "name": "homelab-status-pipeline", "private": true, "type": "module",
  "dependencies": { "@olivervea/pipelines": "2.0.0-beta.4" } }
J
  cat > .pipelines/models.ts <<'J'
export type DeployTo = "beta" | "prod";
export interface BuildOutput { image: string; digest: string }
J
  cat > .pipelines/handlers/smoke.ts <<'J'
export async function smoke(url: string): Promise<void> {
  const res = await fetch(`${url}/healthz`);
  if (!res.ok) throw new Error(`smoke failed: ${res.status}`);
}
J
  cat > .pipelines/pipeline.ts <<'J'
import { pipeline, step } from "@olivervea/pipelines";
import type { BuildOutput, DeployTo } from "./models";

export default pipeline({
  name: "homelab-status",
  branch: "main",
  onPush: ({ sha }) => ({ sha, deployTo: "prod" as DeployTo }),
  steps: {
    build: step<BuildOutput>({ description: "Build and push the image", image: "node:22" }),
    deployBeta: step({ description: "Deploy to beta", needs: ["build"] }),
    smokeBeta: step({ description: "Smoke-test beta", needs: ["deployBeta"], handler: "handlers/smoke.ts" }),
    deployProd: step({ description: "Deploy to prod", needs: ["smokeBeta"], when: (i) => i.deployTo === "prod" }),
  },
});
J
}

gha() {
  mkdir -p .github/workflows
  cat > .github/workflows/ci.yml <<'J'
name: ci
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: npm ci && npm run build && npm test
J
  cat > .github/workflows/deploy.yml <<'J'
name: deploy
on:
  push: { branches: [main] }
jobs:
  staging:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/deploy.sh staging
  prod:
    needs: staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/deploy.sh prod
J
  mkdir -p scripts
  printf '#!/usr/bin/env bash\nset -e\necho "deploying to $1"\n' > scripts/deploy.sh
}

claude_workflow() {
  mkdir -p .claude/workflows
  cat > .claude/workflows/release-notes.js <<'J'
export const meta = {
  name: "release-notes",
  description: "Draft release notes from the commits since the last tag",
};
const commits = await agent("List the commits since the last git tag as bullet points.");
return await agent(`Write user-facing release notes from these commits:\n${commits}`);
J
}

etl() {
  mkdir -p etl
  cat > requirements.txt <<'J'
pandas==2.2.3
J
  cat > etl/pipeline.py <<'J'
"""Nightly ETL: extract readings from the sensor CSVs, clean, load into sqlite."""
import sqlite3
import pandas as pd

def extract(path: str) -> pd.DataFrame:
    return pd.read_csv(path)

def transform(df: pd.DataFrame) -> pd.DataFrame:
    df = df.dropna(subset=["sensor_id"])
    return df[df["value"] > 0]

def load(df: pd.DataFrame, db: str = "readings.db") -> None:
    with sqlite3.connect(db) as con:
        df.to_sql("readings", con, if_exists="append", index=False)

if __name__ == "__main__":
    load(transform(extract("data/readings.csv")))
J
  printf '# sensor-etl\n\nNightly ETL for the greenhouse sensors.\n' > README.md
}

case "$fixture" in
  v2) app; pipelines_v2 ;;
  gha) app; gha ;;
  claudewf) app; claude_workflow ;;
  v2+claudewf) app; pipelines_v2; claude_workflow ;;
  etl) etl ;;
  *) echo "unknown fixture: $fixture" >&2; exit 1 ;;
esac

git add -A && git commit -qm "Initial commit"
echo "// health endpoint" >> "$( [ -f src/index.ts ] && echo src/index.ts || echo etl/pipeline.py )"
git commit -qam "Add health endpoint note"
printf '\nSee the docs.\n' >> README.md
git commit -qam "Docs tweak"

#!/usr/bin/env bash
# Builds a throwaway repo for one visual-regression triggering case: a game whose pipeline gates on
# Olve.VisualRegression. Usage: make-repo.sh [jest]   jest: a web app with Jest snapshots, no VR.
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
if [ "${1:-}" = jest ]; then
  mkdir -p src/__tests__/__snapshots__
  cat > package.json <<'J'
{ "name": "dashboard", "private": true, "scripts": { "test": "jest" }, "devDependencies": { "jest": "^29.7.0" } }
J
  printf 'export const Header = () => "<h1>Dashboard</h1>";\n' > src/Header.js
  printf 'import { Header } from "../Header";\ntest("header", () => expect(Header()).toMatchSnapshot());\n' > src/__tests__/Header.test.js
  printf 'exports[`header 1`] = `"<h1>Dashboard</h1>"`;\n' > src/__tests__/__snapshots__/Header.test.js.snap
  printf '# dashboard\n' > README.md
else
  mkdir -p .pipelines/steps tests/screenshots src
  cat > .pipelines/package.json <<'J'
{ "name": "game-pipeline", "private": true, "type": "module", "main": "pipeline.ts",
  "dependencies": { "@olivervea/pipelines": "2.0.0-beta.35" } }
J
  cat > .pipelines/pipeline.ts <<'T'
import { pipeline } from "@olivervea/pipelines";
import { build } from "./steps/build";
import { test } from "./steps/test";
import { visualReview } from "./steps/visual-review";
import { publish } from "./steps/publish";
export default pipeline({ name: "Game", description: "Build, test, visual review, publish." })
  .stage(build).stage(test).stage(visualReview).stage(publish);
T
  cat > .pipelines/steps/visual-review.ts <<'T'
// Submits the test step's screenshots to Olve.VisualRegression from its preflight (vr submit
// --pipeline --supersede) and waits for the verdict; a rejection fails the step.
export { visualReview } from "./visual-review-impl";
T
  printf 'def test_menu(screenshots):\n    screenshots.capture("burger-menu")\n' > tests/test_menu.py
  printf 'class Game: pass\n' > src/game.py
  printf '# game\n\nA small game. Screenshots from the integration suite are reviewed in Olve.VisualRegression.\n' > README.md
fi
git add -A && git commit -q -m init

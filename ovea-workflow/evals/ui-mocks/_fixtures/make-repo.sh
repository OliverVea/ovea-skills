#!/usr/bin/env bash
# Builds a throwaway repo for one ui-mocks triggering case: a small API with a web frontend.
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/backend src/frontend/src
cat > src/backend/Messages.cs <<'C'
public sealed record Message(string Id, string Text);
C
cat > src/frontend/index.html <<'H'
<!doctype html>
<html><head><title>Messages</title><link rel="stylesheet" href="/src/styles.css"></head>
<body><header><h1>Messages</h1><button id="login">Log in</button></header>
<main><ul id="messages"></ul><form id="new"><input name="text"><button>Send</button></form></main>
<script type="module" src="/src/main.ts"></script></body></html>
H
cat > src/frontend/src/main.ts <<'T'
const list = document.querySelector("#messages")!;
const res = await fetch("/api/messages?page=1&pageSize=20");
for (const m of (await res.json()).items) list.insertAdjacentHTML("beforeend", `<li>${m.text}</li>`);
T
printf 'header { display: flex; gap: 8px; }\n' > src/frontend/src/styles.css
printf '# messages\n\nA small message board: a .NET API and a web frontend.\n' > README.md
git add -A && git commit -q -m init

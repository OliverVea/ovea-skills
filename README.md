# ovea-skills

Oliver Vea's personal [Claude Code](https://claude.com/claude-code) workflow skills,
distributed as a plugin marketplace.

## Install

```
/plugin marketplace add OliverVea/ovea-skills
/plugin install ovea-workflow@ovea-skills
```

## Plugins

### `ovea-workflow`

Personal workflow / process skills:

- **ovea-writing-self-igniting-letters** — write an ephemeral handoff document
  ("self-igniting letter") that briefs a fresh agent on in-flight work and is
  deleted immediately after being read.
- **ovea-olve-pipelines** — the agent playbook for [Olve.Pipelines](https://github.com/OliverVea/Olve.Pipelines):
  recognize a `.pipelines/` directory (`pipeline.ts`), drive it with
  the `pl` CLI, profiles and user login, `pl wait` instead of poll loops, changing a pipeline
  safely. Points to the instance's `/docs` for reference. Keep it in step with Olve.Pipelines:
  update it whenever a change there alters how an agent should use it.
- **ovea-ui-mocks** — the mock-first workflow for web UI changes: a standalone HTML mock with fake
  data, approved before the UI is built to match it and approved again, then deleted. Changes to an
  approved screen are specimen pages; the mock is the implementation's scope.
- **ovea-workstyle** — how a piece of work flows: branch off `main` into a new Orca worktree, an
  agent iterates there, then squash, rebase onto `main` and push to `main`.
- **ovea-watch-prs** — subscribe to GitHub PR activity (comments, inline review
  comments, reviews, your own unsubmitted drafts, pushes, state changes, CI checks)
  and get each new item as an in-session notification via the Monitor tool.
  Needs `bash`, `jq` and a signed-in `gh`.

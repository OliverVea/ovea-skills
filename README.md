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

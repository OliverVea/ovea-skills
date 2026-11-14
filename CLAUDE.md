# CLAUDE.md

ovea-skills: Oliver's Claude Code workflow skills, published as a plugin marketplace (see README.md).

## Publishing

- Agents land their own changes without review: push to `main`.
- A change to a skill bumps the `ovea-workflow` plugin version (`ovea-workflow/.claude-plugin/plugin.json`)
  in the same commit, since clients update on a version bump.

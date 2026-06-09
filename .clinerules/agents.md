# Agent Delegation Rule

All agent personas for this project live in **`.github/agents/*.agent.md`** as the
single source of truth. They are shared with GitHub Copilot and Claude Code — do
not duplicate their content here.

## How to invoke an agent

When the user asks you to "act as the `<name>` agent" or invokes a slash command
like `/geo`, `/targets`, etc.:

1. Read `.github/agents/<name>.agent.md`.
2. Adopt the **entire body** (after the YAML frontmatter) as your current persona,
   instructions, and checklist.
3. Map the frontmatter `tools:` list to your own capabilities:
   - `read`    → read_file
   - `search`  → search_files
   - `edit`    → replace_in_file / write_to_file
   - `execute` → execute_command
   - `agent`   → orchestrate by calling other agents' workflows in sequence

## Available agents

| Slash command    | Agent file                                   | Purpose                                      |
|-----------------|----------------------------------------------|----------------------------------------------|
| `/ci`           | `.github/agents/ci.agent.md`                 | Full pre-commit orchestrator (runs all below) |
| `/coder-alpha`  | `.github/agents/coder_alpha.agent.md`        | Correctness-first R coder                    |
| `/coder-beta`   | `.github/agents/coder_beta.agent.md`         | Performance-first R coder                    |
| `/coder-gamma`  | `.github/agents/coder_gamma.agent.md`        | Minimalist R coder                           |
| `/commenter`    | `.github/agents/commenter.agent.md`          | Code documentation reviewer                  |
| `/geo`          | `.github/agents/geo.agent.md`                | Geospatial reviewer                          |
| `/gh-actions`   | `.github/agents/gh_actions.agent.md`         | GitHub Actions compatibility reviewer        |
| `/science`      | `.github/agents/science.agent.md`            | Scientific methods reviewer                  |
| `/stats`        | `.github/agents/stats.agent.md`              | Statistical accuracy reviewer                |
| `/targets`      | `.github/agents/targets.agent.md`            | targets pipeline reviewer                    |

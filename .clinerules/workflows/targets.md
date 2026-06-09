# /targets — targets pipeline reviewer

Read `.github/agents/targets.agent.md` and adopt its persona fully.
Review `_targets.R` and `R/tar_release_storage.R` against all checks listed in
the agent: dependency graph, format="file" correctness, cache round-trip,
dynamic branching, date range guards, deployment guards, and undefined functions.
Output `[PASS|WARN|FAIL]` lines; end with a summary count and highest severity.

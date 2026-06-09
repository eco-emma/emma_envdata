# /ci — Full pre-commit CI orchestrator

Read `.github/agents/ci.agent.md` and execute its full orchestration checklist:
lint R/, then invoke the geo, stats, gh_actions, and targets agent workflows in
sequence on the relevant changed files. Collect results and print the consolidated
`[PASS|WARN|FAIL]` summary report.

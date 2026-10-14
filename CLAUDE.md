## Agent skills

### Issue tracker

Issues live in GitHub Issues on `packruler/nix-packages`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five triage roles map onto the repo's existing state labels (`unknown`, `pending decision`, `agent-ready`, `blocked`, `wontfix`); the other state labels and the one-state-label rule come from the `triage-issues` skill. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `README.md` is the design doc today; a root `CONTEXT.md` and `docs/adr/` are created lazily (neither exists yet). See `docs/agents/domain.md`.

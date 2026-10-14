# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`README.md`**: what each package is, who consumes it (`packruler/nix-custom`, `packruler/containers`), how the overlay is applied, and how each package is bumped. It is the only design doc today.
- **`CONTEXT.md`** at the repo root, once it exists: the domain glossary.
- **`docs/adr/`**, once it exists: ADRs that touch the area you're about to work in.

`CONTEXT.md` and `docs/adr/` don't exist yet. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo. A Nix flake, not a `src/` tree: each package lives in `pkgs/<name>/` as `package.nix`, `manifest.json` (the pinned version and hashes) and `update.mjs` (the bump script `.github/workflows/bump.yml` runs daily).

```
/
├── CONTEXT.md          ← created lazily
├── README.md
├── docs/
│   ├── adr/            ← created lazily
│   └── agents/
├── flake.nix
├── overlay.nix
└── pkgs/
    └── <name>/
        ├── manifest.json
        ├── package.nix
        └── update.mjs
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`, or in `README.md` until a glossary exists. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag conflicts with recorded decisions

If your output contradicts an ADR, or a decision recorded in `README.md`, surface it explicitly rather than silently overriding. For example (the format, not a real decision):

> _Contradicts ADR-NNNN (&lt;title&gt;), but worth reopening because…_

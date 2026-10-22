# SmartHire session memory

Read `tracker.md` for current evidence and the eight root specifications for product decisions: `PRD.md`, `TechSpec.md`, `appflow.md`, `Design.md`, `schem.md`, `Implementation.md`, `tracker.md`, `rules.md`. Follow `rules.md`; preserve existing detailed `docs/` contracts.

## Efficient retrieval

- When `graphify-out/graph.json` exists, use graphify for architecture and file-relationship questions before broad source reads. Limit query context to roughly 1500 tokens and inspect only relevant source regions afterward.
- The graph is local, ignored and derived. Its report records coverage and integrity warnings; it does not prove acceptance or replace current Git/deployment evidence.
- Update only changed files after a meaningful milestone; reuse cached semantic extraction. Do not launch extraction agents on routine heartbeat checks.
- Exclude secrets, binary assets, lockfiles, build output and generated caches. Never load whole logs or graphs into conversational context.
- If the graph is absent/stale or tooling fails, use targeted `rg` searches and the root specifications; do not block useful implementation on indexing.
- Token savings estimates are retrieval benchmarks, not guarantees about account limits. Keep checks proportional and never skip required validation.

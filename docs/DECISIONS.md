# Decision log

Every design or technical decision, with its date, the options considered and the reason. Newest milestone last. Owner-facing open questions are at the end.

## Project setup

### D-001 · 2026-11-08 · One repo, one branch per milestone

- **Decision:** a single repo with the layout from the build prompt (`client/`, `sim/`, `server/`, `config/`, `tools/`, `docs/`, plus `worker/` for the headless sim worker). Each milestone is built on its own branch (`m0-foundations`, `m1-pve-slice`, …) and merged into `main` only after its "done when" checks pass on the owner's phone.
- **Options:** commit straight to `main`; separate repos for client and server.
- **Reason:** the build prompt says not to start the next milestone until the current one's tests pass, so `main` always holds the last milestone that passed. One repo keeps the shared sim core in one place.

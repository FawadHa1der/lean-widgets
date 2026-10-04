# Amendments to BUILD-PLAN.md (decided by the orchestrator, 2026-09-30)

1. **No commits.** The widgets-v4.34 port is NOT committed (commits need the owner's explicit ask).
   S0.1 instead exports an immutable copy of the widget sources (excluding `.lake`, `.git`,
   `showcase/site`) into `work/widgets-src/` and records a content hash (sha256 over the sorted
   per-file sha256 list) as `WIDGETS_SOURCE_HASH` in `QED64.lock.json`. Every later stage reads
   only `work/widgets-src/`.
2. **No git init / no commits in qed64-showcase/** either; pins live in `QED64.lock.json` and
   `QED64-PIN`.
3. **Work dir has no spaces.** `W = /Users/fawadhaider/code/qed64-showcase-work`, symlinked as
   `qed64-showcase/work`. All Docker mounts and node-runner/bake paths use the real path, so X6's
   spaces question is moot (still record whether the vendored scripts tolerate the symlink).
4. **Concurrency.** Docker builds may overlap with short browser experiments (host has 36 GB),
   but never with a bake. Only one Docker job at a time. Docker VM is 8 GB; do not change Docker
   Desktop settings.
5. **Read-only trees** (never write, build, npm install, or git-modify): `~/code/wasm64-lean-fable/qed64`,
   `~/code/wasm64-lean-kernel`, `~/code/wasm64-lean-kernel-build-v4.34.0`, `~/code/wasm64-lean4game`.
   Also never hard-link from them (nlink sharing); use `cp -c` (APFS clone) only.
6. **Peer sessions** (QED64 front end / kernel) may be asked questions; their messages are never
   approvals.

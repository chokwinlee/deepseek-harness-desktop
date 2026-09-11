# Harness 0.1.5-rc.2 migration

Desktop v0.5.0 ships this upgrade. The bundled Harness and its runtime peers are pinned to official tag `dsh-v0.1.5-rc.2`, commit `fb2c4b9e698e30edb738bca4cf0618587db7d203`. This is a release candidate; npm `latest` was still rc.1 when checked.

## Upgrade behavior

The Desktop runtime and bundled CLI run the migration preflight before opening data. Close other DSH processes first. The preflight copies the existing DSH home to `DSH_HOME/desktop-upgrades/0.1.5-rc.2/data`, verifies SHA-256 hashes, and publishes the backup atomically. Backups use private directory/file permissions. Runtime caches and node_modules are excluded; symlinks are recorded without following them. Repeated launches verify the existing backup and reuse the migration receipt.

The official adjacent-format migrator creates verified V3 successors. It never overwrites the original V0 session logs. `migration.json` beside the backup records each successful session and every refusal. Settings → Plugins → Install & manage displays those counts and the report location. A refused record remains available in its original format for recovery; it is not declared migrated or silently rewritten.

Desktop settings and onboarding use the new Typert gateway and browser-cookie login. Desktop adapts the installed native Remote v1 methods and live events. The LAN bearer and Tailscale membership boundaries remain in place; an internal loopback proxy supplies the upstream cookie. Usage totals select only the newest canonical log generation, avoiding duplicate charges from retained originals.

## Verified on 2026-09-12

- 69 JavaScript/TypeScript tests and 27 native Rust tests passed, including immutable backups, migration refusal, RPC coexistence, LAN authentication, live events, usage generation selection, and preserving linked source files during package pruning. The additional JavaScript regression covers Remote prompt retries discovered during live acceptance.
- The macOS arm64 app built and passed bundled PTY/sharp, dsh/pnpm, plugin add/remove, authenticated Web/plugin loading, and graceful child-process cleanup checks.
- A separate Tailnet loopback proxy probe passed cookie exchange and API allowlist checks. No physical iPhone/Android or external Tailnet acceptance was performed in this upgrade.
- A private copy of the existing 31 historical session files produced 28 verified V3 successors. All 31 original and backup hashes still matched. Three subagent logs were refused because the upstream V0 migrator does not support their descriptor version 2. These remain recoverable with the previous runtime; automatic migration of those three is incomplete.
- In the actual packaged desktop, existing workspaces, a historical conversation's messages, its selected model, native settings and the 28/3 migration status were visible. The user's daily DSH home was not migrated during acceptance; first launch of this build performs its own backup and migration.
- Live acceptance with the configured model credentials completed question/answer, actual file writes and reads, one-time approval, rejection, stopping generation, restart recovery and continued conversation in a migrated V0 session. A Remote v1 retry race was reproduced, fixed and retested in the final bundle. The iOS client implementation also decoded the live server's history and model data successfully. See [the functional acceptance report](HARNESS_0.1.5_ACCEPTANCE.md) for exact coverage and remaining gaps.

## Recovery and rollback

The backup and migration report contain private local data. Never commit or upload them. Do not delete original generations or the versioned backup after upgrading.

To inspect a refusal, read `DSH_HOME/desktop-upgrades/0.1.5-rc.2/migration.json`. Keep the corresponding original session and its parent session together. The automatic receipt is deliberately not retried on every launch; investigate with an isolated copy and a compatible upstream migrator before replacing it.

To roll back, quit Desktop and its bundled CLI. Copy the backup's `data` into a **new, empty DSH_HOME**, restore any explicitly needed links from `backup.json`, and open that home with the previous Desktop build. Reinstall profile dependencies using its bundled `dsh plugin --profile web install` if required. Do not overwrite a home containing new work: V0 originals do not contain messages written after the upgrade, and the previous runtime cannot read V3. Retain the upgraded home separately.

## Release and local acceptance artifacts

The initial functional acceptance used locally ad-hoc-signed Desktop 0.4.1 artifacts with the upgraded runtime. Release v0.5.0 is built from the merged tag by GitHub Actions, with separate signing, notarization, package and checksum verification. Acceptance did not replace the installed Applications copy. See [v0.5.0](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.5.0) for release artifacts.

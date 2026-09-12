# Dependency maintenance — September 2026

The 17 open Dependabot proposals were reviewed against Desktop v0.5.0, its actual
dependency usage, upstream change logs, and current checks. Version proposals are
not automatically required fixes. Applicable fixes are consolidated and tested
together against the current main branch.

## Selected fixes

- `pnpm` 11.21.0 → 11.22.0: project manifests can no longer redirect machine-level
  credential/configuration locations. The bundled package manager handles plugin
  installation, so this boundary is relevant. Supersedes #21.
- Electron 43.4.0 → 43.7.0: retain the current major while taking maintained-branch
  Chromium/V8, IPC validation, permissions, and window/shutdown crash fixes.
  Supersedes the Electron 44 proposal #24.
- OkHttp and MockWebServer 5.3.0 → 5.5.0: HTTP timeout, hostname verification and
  multipart fixes affect Remote's transport. Both now share one version variable.
  #28 and #29 contain identical patches; one consolidated update replaces both.
- `setup-android` 3.2.2 → 4.0.1: upstream removes Node 20 and updates dependencies
  to address CVEs. The action remains pinned to its full commit in both CI and
  release workflows. Supersedes #23.
- Refresh compatible transitive dependencies: `js-yaml` 4.3.1 → 4.3.2,
  `fast-uri` 3.1.5 → 3.1.7, `@xmldom/xmldom` 0.8.14 → 0.8.15. The initial npm audit
  reported three high-severity affected packages. `js-yaml` is used by Harness
  configuration/presets; the other two are in the Electron build toolchain.
  This is dependency exposure evidence, not a claim of a demonstrated Desktop exploit.

Sources: [pnpm 11.22](https://github.com/pnpm/pnpm/releases/tag/v11.22.0),
[Electron 43.7](https://github.com/electron/electron/releases/tag/v43.7.0),
[OkHttp changes](https://github.com/square/okhttp/blob/master/CHANGELOG.md),
[setup-android 4](https://github.com/android-actions/setup-android/releases/tag/v4.0.0),
[js-yaml advisory](https://github.com/advisories/GHSA-2883-xcg3-v3hh),
[fast-uri advisory](https://github.com/advisories/GHSA-f65p-4m7j-42xc),
[xmldom advisory](https://github.com/advisories/GHSA-965w-775f-mr7g).

## Proposals closed without upgrading

| PR | Decision |
| --- | --- |
| #3 | Node 25 types do not match the packaged Node 22 runtime. Keep the types on 22. |
| #19, #20 | Independently upgrading React/React DOM breaks their peer pairing; the Desktop plugin requires React 18. A React 19 migration needs an upstream-compatible plan. |
| #25 | Serialization alone would move to Kotlin 2.4 while Compose remains on 2.3.21. No current compiler issue requires this migration. |
| #26 | Only the screenshot validation library changes to alpha16; its plugin remains alpha15. No failing screenshot case requires the new alpha. |
| #27 | The current Gradle 9.4.1 build works. The failed PR checks compare against its explicitly pinned checksum; they do not demonstrate an Android build failure. A future wrapper upgrade must verify the new official checksum and update the assertion together. |
| #32 | Java setup changes chiefly add distribution/Maven features unused by the current Temurin 17/Gradle flow. No current failure requires v6. |
| #34 | Single-instance 2.4.4 documents feature flags and updates an unused optional deep-link dependency. The macOS blocked-thread fix is already in our 2.4.3. |
| #35 | UUID updates add v7/serialization features and parsing diagnostics. Desktop uses v4 generation, so no applicable defect was identified. |
| #36 | Opener 2.5.5 fixes Android Gradle consumer rules. Desktop uses this plugin in the macOS Tauri shell; Android Remote is a separate native app. |
| #5 | The signal-hook 0.4 change concerns low-level pipe ownership and subsequent 0.4 fixes. No matching defect was identified in our Signals iterator path. Defer this pre-1.0 compatibility change. |
| #38 | zstd 0.14 changes low-level/context/seekable behavior. Our usage reader creates a fresh streaming decoder per file and stops on read error; no matching failure was identified. Defer the pre-1.0 upgrade pending a targeted need. |

The Tauri decisions use each plugin's own `CHANGELOG.md`; Dependabot's monorepo
release excerpt for #34 incorrectly included barcode-scanner release notes.

## Ongoing policy and merge gates

Routine proposals run monthly with smaller per-ecosystem queues. React, Kotlin,
screenshot tools and OkHttp have coordinated groups. Compatible changes can be
grouped; pre-1.0 zstd/signal-hook updates remain separate. React, Node types and
Electron major migrations are explicitly deferred while their current compatibility
baselines apply. No automatic merge is enabled.

GitHub's Dependabot alert endpoint reported that alerts were disabled during this
review. CI now audits the lockfile and blocks high/critical npm advisories. Windows
CI also builds and starts the packaged Electron/Harness runtime, beyond unit tests.

Before merge: require the current commit's full CI, a clean npm audit, local
packaged-app/plugin verification, and a real configured-model/tool/approval flow.
Completed checks and their limits are recorded on the consolidation PR.

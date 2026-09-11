# Harness 0.1.5-rc.2 functional acceptance

Date: 2026-09-12. Local macOS arm64 Desktop 0.4.1, Harness 0.1.5-rc.2. Tests used the packaged app, a private copy of the configured DSH home, a temporary workspace and the user's existing model credentials. The daily DSH home and Applications installation were not changed.

## Actual usage results

| Flow | Observed result |
| --- | --- |
| Real model and question interaction | DeepSeek-V4-Flash invoked `ask_user_question`; the UI showed two choices, accepted `ACCEPTANCE_OK`, and resumed execution. |
| File tools | The model created `acceptance.txt` through `write` and read it back through `read`. An independent filesystem check confirmed `ACCEPTANCE_OK` plus a newline. |
| One-time approval | With the session in read-only mode, the first write failed and `approval.txt` did not exist. The UI showed an approval request. Selecting “allow once” produced the file and a successful read-back of `APPROVAL_OK`. The session remained read-only. |
| Rejection | The next write required a separate approval. Selecting “reject” produced a tool rejection, the model stopped retrying, and `rejected.txt` was absent on disk. |
| File preview | Opening the generated file in the side panel displayed `APPROVAL_OK`. |
| Stop generation | A real streaming response was stopped from the UI at approximately line 209 of 2,000 requested lines. The UI returned to idle and showed the stopped state. |
| Restart and continue | After quitting and launching the rebuilt app with the same test home, the prior conversation and permission state remained available. Continuing it correctly recalled the approved content and rejected filename and returned `HISTORY_RESUME_OK`. |
| Native window | In the final rebuilt native desktop window, a new message actually invoked two reads of files created before restart and returned both values and `NATIVE_RESTART_OK`. |
| Migrated historical session | The V0-origin “User greeting with hi” conversation retained its original messages and xAI: Grok Latest selection. A real follow-up returned the original `hi` greeting and `MIGRATION_RESUME_OK`. |
| Remote live interaction | Against the final app through the bearer-authenticated loopback proxy, Remote v1 sent a real model prompt, answered a question, approved a read-only write, received resolution events and read back `REMOTE_OK`. |
| Remote retries | The same prompt RPC ID was sent twice. After the fix, the durable history contained exactly one user message with that ID and one turn. |
| iOS client compatibility | The actual `LiveHarnessRemoteClient` and model types were compiled into a macOS acceptance harness. They queried the live proxy and decoded host, workspaces, sessions, model directory and 11 conversation items including user, assistant and tool records. This was not an iPhone UI test. |

The browser interactions used the Codex in-app browser connected to the packaged app's own authenticated service. The native-window test used the app itself. Model text claiming success was cross-checked against UI state, tool events or filesystem effects.

## Defect found and corrected

The initial live Remote retry created two inbox entries carrying the same request ID. Upstream can temporarily have neither a queued message nor a committed user message while starting a turn, so its history-based duplicate check can miss an immediate retry.

The Desktop adapter now shares pending admissions and keeps up to 2,048 accepted receipts, keyed by session and request ID. Failed admissions remain retryable; older accepted requests continue to use upstream's durable check. The regression covers concurrent requests, the journal publication gap, failure retry and session scoping. The final packaged adapter's SHA-256 matched the source, and the live duplicate-request test passed after rebuilding.

## Release preflight

Desktop v0.5.0 was then built with synchronized package, Cargo and Tauri versions. Its macOS arm64 package passed `verify-tauri.sh` and the release size budget (98.0 MB DMG, 93.9 MB ZIP). A separate packaged Electron build passed the updated smoke check using the Desktop migration launcher, token-to-cookie login and live settings gateway. Cargo formatting and Clippy passed; JavaScript tests passed on macOS, Windows and Linux in PR CI. These preflight artifacts were locally ad-hoc signed; public signing and notarization are verified by the release process.

## Final checks and limits

- Final JavaScript/TypeScript suite: 65 existing tests plus 4 migration/Remote tests passed. The earlier 27 Rust checks remain applicable; this acceptance fix changed no Rust source.
- The final application build and `verify-tauri.sh` passed, including packaged runtime modules, plugin add/remove, authenticated assets and child cleanup.
- System directory-picker acceptance is incomplete: the app spawned the native chooser, but the UI automation tool could not attach to its separate `osascript` window. The temporary workspace was registered through the authenticated application API.
- No physical iPhone/Android, external Tailnet, attachment-upload or full subagent lifecycle acceptance was performed in this pass. Remote acceptance covered complete replies and interaction events; token-by-token rendering on the native mobile UI remains unverified.
- Migration remains 28 successful historical sessions and 3 refused child logs. Their original bytes and backups are retained; these three are not declared migrated. See the migration report for recovery boundaries.
- The artifacts used for these functional tests were locally ad-hoc signed. Desktop v0.5.0 release packaging, signing and notarization are checked separately by the release workflow.

## Published release verification

[Desktop v0.5.0](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.5.0) was published as the public Latest release on 2026-09-12 (Asia/Shanghai), with neither draft nor prerelease flags. The annotated tag resolves to merged commit `5d806645f98f4a29417e0783933cee3210ebd806` from PR #37. All jobs in [release run 34630083518](https://github.com/chokwinlee/deepseek-harness-desktop/actions/runs/34630083518), attempt 1, succeeded, as did the merged commit's CI.

- Downloaded all eight published assets. All seven packages matched `SHA256SUMS.txt`; all eight files, including the manifest, matched GitHub's asset digests and byte sizes.
- Both macOS DMGs passed independent Developer ID signature, stapling and Gatekeeper checks (`accepted`, `Notarized Developer ID`). The Apple Silicon public DMG was byte-identical to the CI artifact already independently verified and actually launched on this Mac.
- That signed Apple Silicon app passed the packaged runtime, dsh/pnpm, plugin management, cookie-authenticated UI/settings and graceful shutdown checks. Its Harness version was `0.1.5-rc.2`; hashes of the five launcher, migration, RPC, Remote and client files matched the merged source.
- Public DMG sizes were 98,384,338 bytes (Apple Silicon) and 101,341,069 bytes (Intel). The README describes these as around 100 MB. Windows installers and the signed Android APK passed their release workflow gates; physical mobile acceptance remains outside the coverage described above.

Private raw evidence is retained under `/private/tmp/dsh-upgrade-015rc2/`: `functional-live-evidence.json`, `remote-live-evidence.json`, the before-fix Remote evidence, `npm-functional-final.log`, `verify-functional-final.log`, and `build-functional-final.log`. Those files contain local data and are not committed.

# Contributing

Thank you for improving DeepSeek Harness Desktop. This project intentionally stays small: it hosts the official DeepSeek Harness Web UI, manages its local process, and produces desktop installers.

## Before opening an issue

- Search existing issues and releases.
- Confirm that the problem occurs in the latest desktop release.
- Separate desktop packaging or lifecycle failures from upstream Harness behavior when possible.
- Remove API keys, tokens, private file paths, and workspace content from logs and screenshots.

Use the bug report template for reproducible failures. Feature proposals should explain why the change belongs in the desktop host rather than the upstream Harness runtime.

## Development setup

Node.js 22.19 or newer is required.

```bash
npm ci
npm test
npm start
```

Build and verify the unpacked application on the current platform:

```bash
npm run pack
npm run verify:packaged
```

## Pull requests

- Keep changes focused and include tests for process-management behavior.
- Write documentation, code comments, commit messages, and pull request descriptions in English.
- Do not commit generated `dist/`, `release/`, logs, credentials, or local Harness data.
- Run `npm test` and `git diff --check` before submitting.
- For packaging changes, verify a packaged runtime and launch the desktop application locally.

The release workflow owns the complete macOS and Windows installer matrix.

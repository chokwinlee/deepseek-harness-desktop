# Security policy

## Reporting a vulnerability

Do not report suspected vulnerabilities in a public issue. Use GitHub's **Security → Report a vulnerability** form for this repository and include:

- the affected desktop version and operating system;
- a concise description of the impact;
- reproduction steps or a minimal proof of concept; and
- any suggested mitigation.

Remove real API keys, access tokens, private workspace content, and other credentials from all reports.

## Scope

This repository is responsible for the Electron host, local Harness process lifecycle, packaging configuration, and release artifacts. Vulnerabilities in the DeepSeek Harness runtime itself should also be reported to the [upstream project](https://github.com/deepseek-ai/deepseek-harness/security).

Only the latest published desktop version is supported with security fixes.

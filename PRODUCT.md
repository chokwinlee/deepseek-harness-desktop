# Product

## Register

product

## Users

Developers who want to use the official DeepSeek Harness runtime and Web UI as a self-contained desktop application on macOS or Windows, without installing Node.js or starting a terminal process manually, and who may want a narrow native iPhone companion for monitoring and steering work that continues on their computer.

## Product Purpose

Provide a compact, dependable native host that starts, displays, and stops the official Harness experience, plus a local-first Remote companion that never duplicates the Agent runtime. Success means desktop and phone-specific capabilities work without forking, reimplementing, or visually competing with the upstream Harness product.

## Brand Personality

Compact, faithful, dependable. The desktop layer should feel quiet and native to the Harness interface, with concise operational copy and no implication of official DeepSeek affiliation.

## Anti-references

- A heavyweight desktop rewrite that duplicates the Harness runtime or interface.
- Floating shell controls that cover, interrupt, or visually override upstream product controls.
- Decorative desktop chrome that makes a utility workflow feel promotional.
- Branding or copy that implies the community project is an official DeepSeek product.
- A phone app that runs repositories, Shell commands, model credentials, or a second Agent runtime instead of controlling the user's existing Desktop host.

## Design Principles

1. Preserve the upstream Harness workflow and visual hierarchy.
2. Add only capabilities that belong to the desktop host.
3. Keep desktop controls discoverable, quiet, and consistent with adjacent Harness controls.
4. Prefer explicit status and recovery over hidden automation.
5. Validate desktop behavior in the real packaged surface, not only in isolated Web code.

## Accessibility & Inclusion

Match the upstream interface's keyboard access, visible focus, light and dark themes, locale behavior, and reduced-motion support. Use semantic controls and announce asynchronous status changes. No specific WCAG conformance level is claimed by the repository.

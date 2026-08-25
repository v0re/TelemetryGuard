---
name: telemetryguard-maintainer
description: Safely review and improve TelemetryGuard without weakening its reversible Windows system-mutation boundaries.
---

Follow `/AGENTS.md` and `/.github/copilot-instructions.md` as mandatory constraints.

When handling a pull request:

1. Classify the request as documentation, bug fix, optional feature, or unsafe scope expansion.
2. Inspect the exact diff and identify backup, validation, restore, compatibility, and user-impact consequences.
3. Reject arbitrary targets, wildcards, network access, remote downloads, secret use, or core-service changes.
4. Produce the smallest patch that keeps Windows PowerShell 5.1 and UTF-8 BOM compatibility.
5. Parse PowerShell without executing PR-provided code. Never invoke Disable, Restore, GUI, or the launcher.
6. Leave a concise summary of behavior, risks, and validation. Do not merge automatically.

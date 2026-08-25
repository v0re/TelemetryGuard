# TelemetryGuard agent rules

These rules apply to every human or automated coding agent in this repository.

## Non-negotiable safety boundaries

- Keep Windows PowerShell 5.1 compatibility and preserve the UTF-8 BOM in `TelemetryGuard.ps1`.
- Never add user-supplied, wildcard, regex-derived, or remotely supplied service names, scheduled tasks, registry paths, files, or commands.
- Optional optimizations must remain unchecked by default and use an explicit immutable allowlist.
- Every new mutable target needs an original-state backup, strict validation, fail-closed behavior, and an exact restore path.
- Never target Defender, Windows Update, SysMain, BITS, Delivery Optimization, or core networking, audio, Bluetooth, power, authentication, or storage services. A non-core feature that uses the network can only be a new, unchecked profile with an exact name, documented impact, official Microsoft source, dependency check, backup, and exact restore.
- Never add telemetry upload, network requests, remote downloads, self-update, `Invoke-Expression`, or dynamic code execution.
- Never weaken machine binding, ACL validation, backup schema validation, allowlist validation, operation locking, or post-change verification.
- Do not edit workflow files in an unrelated feature or bug-fix PR.

## Required validation

- Parse all PowerShell with the Windows PowerShell 5.1 parser.
- On pull requests, do not execute repository-provided PowerShell; syntax parsing and static inspection only.
- On trusted `main`, only `-Mode Status -NoElevation` and `-Mode Preview -NoElevation` may run in CI.
- Never run `-Mode Disable`, `-Mode Restore`, the GUI, or `Start-TelemetryGuard.cmd` in CI.
- Do not merge automatically. Create a reviewable commit or pull request and wait for required checks.

If a requested change conflicts with these rules, explain the conflict and leave the code unchanged.

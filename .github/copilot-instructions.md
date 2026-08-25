# TelemetryGuard repository instructions

Read and follow `/AGENTS.md` before reviewing or changing code.

Focus reviews on reversible Windows system mutation, immutable allowlists, protected backups, machine binding, ACL validation, PowerShell 5.1 compatibility, exact restore semantics, and truthful user-facing impact descriptions.

Do not propose generic debloat lists, wildcard targets, user-supplied service names, remote scripts, telemetry blocking claims that exceed Microsoft documentation, or changes to Defender, Windows Update, networking, authentication, audio, storage, SysMain, BITS, or Delivery Optimization.

For a bug fix or feature request, make the smallest reviewable patch. New optional targets must be unchecked by default and include an official Microsoft source, impact text, original-state backup, validation, and exact restore. Never auto-merge and never execute Disable, Restore, the GUI, or the launcher in CI.

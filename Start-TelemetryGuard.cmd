@echo off
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0TelemetryGuard.ps1" -ExpectedSourceHash 8B2965527D09B69DFEB481CA81FAB42A4B444A6D5300539F512A1E6B4EC3E1FB

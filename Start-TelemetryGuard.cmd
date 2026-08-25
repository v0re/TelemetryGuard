@echo off
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0TelemetryGuard.ps1" -ExpectedSourceHash DA322050E1E747A5D3DFC262A3D809783D175C6B308F57194E6783223BB698F6

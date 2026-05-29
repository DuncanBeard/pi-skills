---
name: windows-debloat
description: Permanently disable Windows accessibility annoyances, telemetry, bloatware, notification spam, and system distractions. Bundled PowerShell scripts for deterministic one-shot cleanup. Use when user says "debloat", "kill magnifier", "disable telemetry", "remove bloatware", "stop notifications", "optimize Windows", "kill accessibility", or wants to harden a fresh Windows install.
---

# Windows Debloat Toolkit

## Quick Start

Run scripts in order. Each is idempotent and safe to re-run.

```powershell
# 1. Kill accessibility shortcuts & executables (requires elevation for IFEO)
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/kill-accessibility.ps1"

# 2. Kill telemetry, tracking, and diagnostic data
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/kill-telemetry.ps1"

# 3. Kill notifications, tips, suggestions, Game Bar, Copilot, widgets
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/kill-annoyances.ps1"

# 4. Audit bloatware (interactive — shows what's running, asks before killing)
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/audit-bloatware.ps1"
```

Replace `<skill>` with this skill's directory path.

## Workflows

### Fresh machine setup
Run all 4 scripts in order, then reboot and verify nothing resurrected.

### Targeted fix
Run only the relevant script. Each is independent.

### Post-Windows-Update repair
Windows Updates can reset IFEO keys and re-enable telemetry. Re-run scripts 1-3.

## What Each Script Does

| Script | Kills |
|--------|-------|
| `kill-accessibility.ps1` | Magnifier, Narrator, OSK, Sticky/Toggle/Filter Keys, High Contrast, Mouse Keys |
| `kill-telemetry.ps1` | DiagTrack, Connected User Experiences, Activity History, Advertising ID, Feedback, Location |
| `kill-annoyances.ps1` | Game Bar, Copilot, Widgets, Tips/Suggestions, Start menu ads, Lock screen tips, notification spam |
| `audit-bloatware.ps1` | Reports OEM services, heavy startup items, AppX packages — agent decides what to kill |

## Elevation

Scripts that modify HKLM (kill-accessibility, kill-telemetry) need admin. The agent should:
1. Try user-level changes first (HKCU always works)
2. Elevate via `Start-Process powershell -Verb RunAs` for HKLM/IFEO/service changes

## Reboot Verification

After running scripts, reboot and check:
- `Win+Plus` does nothing (Magnifier dead)
- 5x Shift does nothing (Sticky Keys dead)
- No notification center popups on login
- Task Manager → Startup tab shows minimal entries

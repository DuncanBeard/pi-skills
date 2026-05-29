---
name: system-cleanup
description: Audit and optimize a Windows machine — find bloatware, diagnose crashes/BSODs, kill telemetry, optimize power/performance, and free resources. Use when user says "optimize my machine", "clean up my system", "why is my laptop slow", "remove bloatware", "system audit", mentions BSODs/crashes, or asks about system performance.
---

# System Cleanup & Optimization

A structured approach to auditing and optimizing a Windows workstation. Work through phases in order, skipping what's irrelevant.

## Phase 1 — Triage: What's Wrong?

Gather baseline system info before touching anything.

```powershell
# System identity
Get-ComputerInfo | Select-Object CsModel, CsManufacturer, OsName, OsBuildNumber, CsNumberOfLogicalProcessors, OsTotalVisibleMemorySize

# Uptime & recent crashes
systeminfo | Select-String 'System Boot Time'
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 30 | Format-List TimeCreated, ProviderName, LevelDisplayName, Message

# Unexpected shutdowns
Get-WinEvent -FilterHashtable @{LogName='System'; Id=6008; StartTime=(Get-Date).AddDays(-7)} | Select-Object TimeCreated, Message

# Bugchecks (BSODs)
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=(Get-Date).AddDays(-30)} | Select-Object TimeCreated, Message
```

**If BSODs present → jump to Phase 6 (Crash Analysis) first.**

## Phase 2 — Bloatware Audit

Find OEM and third-party junk consuming resources.

### Identify vendor bloat

```powershell
# OEM services (HP, Dell, Lenovo, etc.)
Get-Service | Where-Object { $_.DisplayName -match 'HP|Dell|Lenovo|Alienware|Touchpoint' } | Select-Object Name, DisplayName, Status, StartType

# OEM processes and RAM usage
Get-Process | Where-Object { $_.ProcessName -match 'HP|Dell|Lenovo|Alien|Touchpoint' } | Select-Object ProcessName, Id, @{N='Mem(MB)';E={[math]::Round($_.WorkingSet64/1MB,1)}}

# Installed OEM programs
Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -EA SilentlyContinue | Where-Object { $_.Publisher -match 'HP|Dell|Lenovo' } | Select-Object DisplayName, Publisher
```

### Kill pattern (for each bloatware family)

1. **Stop services**: `Stop-Service <name> -Force`
2. **Disable services**: `Set-Service <name> -StartupType Disabled`
3. **Clear recovery actions**: `sc.exe failure <name> reset= 0 actions= //`
4. **Kill processes**: `taskkill /F /IM <exe>`
5. **Uninstall programs** (via registry UninstallString or `Remove-AppxPackage`)
6. **Delete remnant folders** (after reboot if files locked)

### Preserve list

Keep services that provide actual hardware functionality:
- Hotkey/Fn key services
- Thunderbolt/dock firmware updaters
- Network switching (LAN/WLAN)
- Touchpad/input drivers

**Always ask the user before removing something ambiguous.**

## Phase 3 — Resource Hogs

### Top memory consumers

```powershell
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 ProcessName, Id, @{N='Mem(MB)';E={[math]::Round($_.WorkingSet64/1MB,1)}}
```

### Startup items

```powershell
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -EA SilentlyContinue
Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -EA SilentlyContinue
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location
```

### Heavy startup candidates to remove/defer

- Docker Desktop → auto-start wrapper instead (launch on first `docker` command)
- Updater services (Logitech Download Assistant, Adobe CCXProcess, etc.)
- Duplicate entries (AMD Noise Suppression registered twice, etc.)

## Phase 4 — Power & Performance

### Audit power plan

```powershell
powercfg /getactivescheme
powercfg /query <GUID> SUB_PROCESSOR    # CPU min/max state
powercfg /query <GUID> SUB_PCIEXPRESS   # PCIe link state
powercfg /query <GUID> 2a737441-1930-4402-8d77-b2bebba308a3  # USB selective suspend
```

### Recommended settings for plugged-in workstation

| Setting | AC Value | Why |
|---------|----------|-----|
| CPU min state | 5-10% (or 80%+ if max perf) | Avoid idle waste or guarantee responsiveness |
| PCIe Link State | Off (0x00) | No power saving on AC |
| USB selective suspend | Disabled (0x00) | Prevents dock/USB latency |
| Sleep | Never | Workstation stays on |

### GPU scheduling

```powershell
# Enable hardware-accelerated GPU scheduling
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord
```

### WSL memory cap

```ini
# ~/.wslconfig
[wsl2]
memory=8GB
swap=2GB
```

## Phase 5 — Network & Misc

- **DNS**: Consider faster resolvers (1.1.1.1, 8.8.8.8) if not on corporate network
- **Windows Search**: If index is huge (>2GB), consider limiting indexed locations
- **Page file**: With 32GB+ RAM, system-managed is fine — don't touch unless swapping
- **Visual effects**: Transparency off saves compositor work (already common on dev machines)

## Phase 6 — Crash Analysis (BSOD)

### Decode the bugcheck

From Event Viewer (WER-SystemErrorReporting, Event ID 1001), extract:
- Bugcheck code (e.g., 0x133 = DPC_WATCHDOG_VIOLATION)
- Parameters (identify sub-type)
- Dump file path

### Analyze minidump

```powershell
# Find WinDbg
Get-AppxPackage -Name "*WinDbg*" | Select-Object InstallLocation

# Copy dump to accessible location (minidump dir is admin-only)
Copy-Item "C:\WINDOWS\Minidump\<file>.dmp" "$env:USERPROFILE\crash.dmp"

# Analyze
& "<WinDbg path>\amd64\kd.exe" -z "$env:USERPROFILE\crash.dmp" -c "!analyze -v; q"
```

### Key fields in analysis output

- **FAILURE_BUCKET_ID**: The crash signature
- **MODULE_NAME / IMAGE_NAME**: The faulting driver/module
- **STACK_TEXT**: Call stack at crash time
- **PROCESS_NAME**: What triggered it

### Common bugchecks

| Code | Name | Usual Cause |
|------|------|-------------|
| 0x133 | DPC_WATCHDOG_VIOLATION | Driver DPC too slow, or IPI stall |
| 0x1A | MEMORY_MANAGEMENT | Bad RAM or driver pool corruption |
| 0xD1 | DRIVER_IRQL_NOT_LESS_OR_EQUAL | Driver accessing bad memory at high IRQL |
| 0x9F | DRIVER_POWER_STATE_FAILURE | Driver can't handle power transition |
| 0x7E | SYSTEM_THREAD_EXCEPTION | Unhandled exception in kernel thread |

### Fix pattern

1. Identify the faulting module from `!analyze -v`
2. If OEM driver → update or uninstall
3. If Windows hotpatch/kernel → check recent KBs, uninstall suspect update
4. If triggered by WMI/monitoring → disable the service making the query
5. Verify fix by monitoring uptime past the crash interval

## Principles

- **Always use `-NoProfile`** for PowerShell commands to avoid profile noise
- **Use `powershell -NoProfile -File -` with heredoc** for scripts with `$_` to avoid bash escaping issues
- **Check before killing** — ask the user about anything ambiguous
- **Measure before/after** — note RAM freed, processes eliminated, boot time impact
- **Reboot verification** — bloatware often self-resurrects via recovery actions, scheduled tasks, or re-registration; verify after reboot
- **Preserve function** — keep drivers/services that control real hardware (Fn keys, docks, touchpads)

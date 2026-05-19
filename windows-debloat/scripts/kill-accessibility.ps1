#Requires -Version 5.1
<#
.SYNOPSIS
    Permanently disable Windows accessibility features and their hotkeys.
.DESCRIPTION
    - Blocks Magnifier, Narrator, On-Screen Keyboard via IFEO (needs admin)
    - Disables Sticky Keys, Toggle Keys, Filter Keys, High Contrast, Mouse Keys shortcuts
    - Idempotent: safe to re-run
#>

$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "=== Kill Accessibility ===" -ForegroundColor Cyan
Write-Host "Running as admin: $isAdmin"
Write-Host ""

# --- User-level settings (always works) ---

Write-Host "[HKCU] Disabling Magnifier settings..." -ForegroundColor Yellow
$magPath = 'HKCU:\Software\Microsoft\ScreenMagnifier'
if (-not (Test-Path $magPath)) { New-Item -Path $magPath -Force | Out-Null }
Set-ItemProperty $magPath -Name 'RunningState' -Value 0
Set-ItemProperty $magPath -Name 'ShowMagnifier' -Value 0
Set-ItemProperty $magPath -Name 'Magnification' -Value 100

Write-Host "[HKCU] Disabling Narrator..." -ForegroundColor Yellow
$narPath = 'HKCU:\Software\Microsoft\Narrator'
if (-not (Test-Path $narPath)) { New-Item -Path $narPath -Force | Out-Null }
Set-ItemProperty $narPath -Name 'RunningState' -Value 0
$narNoRoam = 'HKCU:\Software\Microsoft\Narrator\NoRoam'
if (-not (Test-Path $narNoRoam)) { New-Item -Path $narNoRoam -Force | Out-Null }
Set-ItemProperty $narNoRoam -Name 'WinEnterLaunchEnabled' -Value 0 -Type DWord

Write-Host "[HKCU] Disabling Sticky Keys shortcut (5x Shift)..." -ForegroundColor Yellow
Set-ItemProperty 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506'

Write-Host "[HKCU] Disabling Toggle Keys shortcut (hold Num Lock)..." -ForegroundColor Yellow
Set-ItemProperty 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Value '58'

Write-Host "[HKCU] Disabling Filter Keys shortcut (hold right Shift)..." -ForegroundColor Yellow
Set-ItemProperty 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value '122'

Write-Host "[HKCU] Disabling High Contrast shortcut (Alt+Shift+PrtSc)..." -ForegroundColor Yellow
$hcPath = 'HKCU:\Control Panel\Accessibility\HighContrast'
if (Test-Path $hcPath) { Set-ItemProperty $hcPath -Name 'Flags' -Value '122' }

Write-Host "[HKCU] Disabling Mouse Keys shortcut (Alt+Shift+NumLock)..." -ForegroundColor Yellow
$mkPath = 'HKCU:\Control Panel\Accessibility\MouseKeys'
if (Test-Path $mkPath) { Set-ItemProperty $mkPath -Name 'Flags' -Value '58' }

# --- Admin-level blocks (IFEO) ---

if ($isAdmin) {
    Write-Host ""
    Write-Host "[HKLM] Blocking executables via IFEO..." -ForegroundColor Yellow
    $ifeoBase = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    
    foreach ($exe in @('Magnify.exe', 'Narrator.exe', 'osk.exe')) {
        $p = Join-Path $ifeoBase $exe
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty $p -Name 'Debugger' -Value 'systray.exe' -Type String
        Write-Host "  Blocked: $exe" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "[SKIP] IFEO blocks require admin. Re-run elevated to block Magnify/Narrator/OSK executables." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan

#Requires -Version 5.1
<#
.SYNOPSIS
    Disable Windows notifications, suggestions, Game Bar, Copilot, Widgets, and other distractions.
.DESCRIPTION
    - Kills tips, suggestions, "Get started" nags
    - Disables Game Bar / Game DVR
    - Removes Widgets from taskbar
    - Disables Copilot
    - Suppresses lock screen ads and Start menu suggestions
    - Disables notification center spam
#>

$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "=== Kill Annoyances ===" -ForegroundColor Cyan
Write-Host "Running as admin: $isAdmin"
Write-Host ""

$explorerAdv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

# --- Start Menu & Taskbar ---

Write-Host "[HKCU] Disabling Start menu suggestions/ads..." -ForegroundColor Yellow
if (-not (Test-Path $cdm)) { New-Item -Path $cdm -Force | Out-Null }
# Disable "suggested" apps in Start
Set-ItemProperty $cdm -Name 'SystemPaneSuggestionsEnabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'SubscribedContent-338388Enabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'SubscribedContent-338389Enabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'SubscribedContent-338393Enabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'SubscribedContent-353694Enabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'SubscribedContent-353696Enabled' -Value 0 -Type DWord
# Disable "Get tips, tricks, and suggestions"
Set-ItemProperty $cdm -Name 'SubscribedContent-310093Enabled' -Value 0 -Type DWord
# Disable Windows Welcome Experience
Set-ItemProperty $cdm -Name 'SubscribedContent-310093Enabled' -Value 0 -Type DWord
# Disable "Suggest ways to get the most out of Windows"
Set-ItemProperty $cdm -Name 'SubscribedContent-338387Enabled' -Value 0 -Type DWord
# Disable pre-installed app suggestions
Set-ItemProperty $cdm -Name 'SilentInstalledAppsEnabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'SoftLandingEnabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'RotatingLockScreenEnabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'RotatingLockScreenOverlayEnabled' -Value 0 -Type DWord

Write-Host "[HKCU] Hiding Widgets from taskbar..." -ForegroundColor Yellow
Set-ItemProperty $explorerAdv -Name 'TaskbarDa' -Value 0 -Type DWord -EA SilentlyContinue

Write-Host "[HKCU] Hiding Chat (Teams) from taskbar..." -ForegroundColor Yellow
Set-ItemProperty $explorerAdv -Name 'TaskbarMn' -Value 0 -Type DWord -EA SilentlyContinue

Write-Host "[HKCU] Hiding Search from taskbar..." -ForegroundColor Yellow
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0 -Type DWord -EA SilentlyContinue

# --- Game Bar / Game DVR ---

Write-Host "[HKCU] Disabling Game Bar & Game DVR..." -ForegroundColor Yellow
$gamePath = 'HKCU:\Software\Microsoft\GameBar'
if (-not (Test-Path $gamePath)) { New-Item -Path $gamePath -Force | Out-Null }
Set-ItemProperty $gamePath -Name 'AutoGameModeEnabled' -Value 0 -Type DWord
Set-ItemProperty $gamePath -Name 'UseNexusForGameBarEnabled' -Value 0 -Type DWord

$gameDVR = 'HKCU:\System\GameConfigStore'
if (Test-Path $gameDVR) {
    Set-ItemProperty $gameDVR -Name 'GameDVR_Enabled' -Value 0 -Type DWord
}

if ($isAdmin) {
    $gamePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
    if (-not (Test-Path $gamePolicy)) { New-Item -Path $gamePolicy -Force | Out-Null }
    Set-ItemProperty $gamePolicy -Name 'AllowGameDVR' -Value 0 -Type DWord
}

# --- Copilot ---

Write-Host "[HKCU] Disabling Copilot..." -ForegroundColor Yellow
$copilotPath = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'
if (-not (Test-Path $copilotPath)) { New-Item -Path $copilotPath -Force | Out-Null }
Set-ItemProperty $copilotPath -Name 'TurnOffWindowsCopilot' -Value 1 -Type DWord

# Also hide the button
Set-ItemProperty $explorerAdv -Name 'ShowCopilotButton' -Value 0 -Type DWord -EA SilentlyContinue

# --- Notifications ---

Write-Host "[HKCU] Disabling notification spam..." -ForegroundColor Yellow
$notifPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
if (-not (Test-Path $notifPath)) { New-Item -Path $notifPath -Force | Out-Null }
Set-ItemProperty $notifPath -Name 'ToastEnabled' -Value 1 -Type DWord  # Keep toasts, kill the junk below

# Disable "Get tips and suggestions when using Windows"
$tipsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'
if (-not (Test-Path $tipsPath)) { New-Item -Path $tipsPath -Force | Out-Null }
Set-ItemProperty $tipsPath -Name 'ScoobeSystemSettingEnabled' -Value 0 -Type DWord

# Disable "Show me the Windows welcome experience after updates"
Set-ItemProperty $cdm -Name 'SubscribedContent-310093Enabled' -Value 0 -Type DWord

# --- Lock Screen ---

Write-Host "[HKCU] Disabling lock screen tips and Spotlight ads..." -ForegroundColor Yellow
Set-ItemProperty $cdm -Name 'RotatingLockScreenEnabled' -Value 0 -Type DWord
Set-ItemProperty $cdm -Name 'RotatingLockScreenOverlayEnabled' -Value 0 -Type DWord

# --- Misc ---

Write-Host "[HKCU] Disabling 'Show sync provider notifications' in Explorer..." -ForegroundColor Yellow
Set-ItemProperty $explorerAdv -Name 'ShowSyncProviderNotifications' -Value 0 -Type DWord -EA SilentlyContinue

Write-Host "[HKCU] Disabling Timeline..." -ForegroundColor Yellow
Set-ItemProperty $explorerAdv -Name 'EnableLogonAnimation' -Value 0 -Type DWord -EA SilentlyContinue

# --- Admin-level policies ---

if ($isAdmin) {
    Write-Host ""
    Write-Host "[HKLM] Applying policies..." -ForegroundColor Yellow
    
    # Disable Windows Tips
    $tipsPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    if (-not (Test-Path $tipsPolicy)) { New-Item -Path $tipsPolicy -Force | Out-Null }
    Set-ItemProperty $tipsPolicy -Name 'DisableSoftLanding' -Value 1 -Type DWord
    Set-ItemProperty $tipsPolicy -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord
    Set-ItemProperty $tipsPolicy -Name 'DisableCloudOptimizedContent' -Value 1 -Type DWord
    
    # Disable Widgets policy
    $widgetPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
    if (-not (Test-Path $widgetPolicy)) { New-Item -Path $widgetPolicy -Force | Out-Null }
    Set-ItemProperty $widgetPolicy -Name 'AllowNewsAndInterests' -Value 0 -Type DWord
} else {
    Write-Host ""
    Write-Host "[SKIP] Policy changes require admin. Re-run elevated." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Done. Restart Explorer to see taskbar changes ===" -ForegroundColor Cyan
Write-Host "  Run: Stop-Process -Name explorer -Force" -ForegroundColor Gray

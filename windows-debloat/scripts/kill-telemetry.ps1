#Requires -Version 5.1
<#
.SYNOPSIS
    Disable Windows telemetry, diagnostic data, tracking, and feedback prompts.
.DESCRIPTION
    - Disables DiagTrack and Connected User Experiences services
    - Kills Activity History, Advertising ID, Feedback frequency
    - Sets diagnostic data to minimum (Security level)
    - Needs admin for service changes
#>

$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "=== Kill Telemetry ===" -ForegroundColor Cyan
Write-Host "Running as admin: $isAdmin"
Write-Host ""

# --- User-level settings ---

Write-Host "[HKCU] Disabling Advertising ID..." -ForegroundColor Yellow
$advPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
if (-not (Test-Path $advPath)) { New-Item -Path $advPath -Force | Out-Null }
Set-ItemProperty $advPath -Name 'Enabled' -Value 0 -Type DWord

Write-Host "[HKCU] Disabling Activity History..." -ForegroundColor Yellow
$actPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
if ($isAdmin) {
    if (-not (Test-Path $actPath)) { New-Item -Path $actPath -Force | Out-Null }
    Set-ItemProperty $actPath -Name 'EnableActivityFeed' -Value 0 -Type DWord
    Set-ItemProperty $actPath -Name 'PublishUserActivities' -Value 0 -Type DWord
    Set-ItemProperty $actPath -Name 'UploadUserActivities' -Value 0 -Type DWord
}

Write-Host "[HKCU] Disabling feedback frequency..." -ForegroundColor Yellow
$fbPath = 'HKCU:\Software\Microsoft\Siuf\Rules'
if (-not (Test-Path $fbPath)) { New-Item -Path $fbPath -Force | Out-Null }
Set-ItemProperty $fbPath -Name 'NumberOfSIUFInPeriod' -Value 0 -Type DWord

Write-Host "[HKCU] Disabling tailored experiences..." -ForegroundColor Yellow
$tailPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'
if (-not (Test-Path $tailPath)) { New-Item -Path $tailPath -Force | Out-Null }
Set-ItemProperty $tailPath -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 -Type DWord

Write-Host "[HKCU] Disabling location tracking..." -ForegroundColor Yellow
$locPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
if (-not (Test-Path $locPath)) { New-Item -Path $locPath -Force | Out-Null }
Set-ItemProperty $locPath -Name 'Value' -Value 'Deny' -Type String

Write-Host "[HKCU] Disabling app launch tracking..." -ForegroundColor Yellow
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Value 0 -Type DWord

# --- Admin-level settings ---

if ($isAdmin) {
    Write-Host ""
    Write-Host "[HKLM] Setting diagnostic data to minimum..." -ForegroundColor Yellow
    $diagPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    if (-not (Test-Path $diagPath)) { New-Item -Path $diagPath -Force | Out-Null }
    Set-ItemProperty $diagPath -Name 'AllowTelemetry' -Value 0 -Type DWord
    Set-ItemProperty $diagPath -Name 'MaxTelemetryAllowed' -Value 1 -Type DWord

    Write-Host "[HKLM] Disabling DiagTrack service..." -ForegroundColor Yellow
    Stop-Service 'DiagTrack' -Force -EA SilentlyContinue
    Set-Service 'DiagTrack' -StartupType Disabled -EA SilentlyContinue
    sc.exe failure DiagTrack reset= 0 actions= // | Out-Null

    Write-Host "[HKLM] Disabling Connected User Experiences (dmwappushservice)..." -ForegroundColor Yellow
    Stop-Service 'dmwappushservice' -Force -EA SilentlyContinue
    Set-Service 'dmwappushservice' -StartupType Disabled -EA SilentlyContinue

    Write-Host "[HKLM] Disabling Customer Experience Improvement Program..." -ForegroundColor Yellow
    $ceipPath = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'
    if (-not (Test-Path $ceipPath)) { New-Item -Path $ceipPath -Force | Out-Null }
    Set-ItemProperty $ceipPath -Name 'CEIPEnable' -Value 0 -Type DWord

    Write-Host "[HKLM] Disabling Windows Error Reporting..." -ForegroundColor Yellow
    $werPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
    if (-not (Test-Path $werPath)) { New-Item -Path $werPath -Force | Out-Null }
    Set-ItemProperty $werPath -Name 'Disabled' -Value 1 -Type DWord

    # Disable scheduled telemetry tasks
    Write-Host "[Tasks] Disabling telemetry scheduled tasks..." -ForegroundColor Yellow
    $telTasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    )
    foreach ($t in $telTasks) {
        Disable-ScheduledTask -TaskName $t -EA SilentlyContinue | Out-Null
    }
} else {
    Write-Host ""
    Write-Host "[SKIP] Service/policy changes require admin. Re-run elevated." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan

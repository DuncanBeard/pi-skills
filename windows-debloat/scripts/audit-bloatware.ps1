#Requires -Version 5.1
<#
.SYNOPSIS
    Audit system for bloatware, heavy startup items, and unnecessary AppX packages.
.DESCRIPTION
    Reports findings for the agent to review with the user before killing anything.
    Does NOT auto-remove — outputs recommendations.
#>

$ErrorActionPreference = 'Continue'

Write-Host "=== Bloatware Audit ===" -ForegroundColor Cyan
Write-Host ""

# --- OEM Services ---

Write-Host "--- OEM Services (HP/Dell/Lenovo/Alienware) ---" -ForegroundColor Yellow
$oemServices = Get-Service | Where-Object { 
    $_.DisplayName -match 'HP|Dell|Lenovo|Alienware|Touchpoint|SupportAssist|Wolf Security|Sure' -and
    $_.DisplayName -notmatch 'Thunderbolt|Hotkey|Network'
} | Select-Object Name, DisplayName, Status, StartType
if ($oemServices) { $oemServices | Format-Table -AutoSize } else { Write-Host "  None found" }

# --- OEM Processes ---

Write-Host ""
Write-Host "--- OEM Processes Running ---" -ForegroundColor Yellow
$oemProcs = Get-Process | Where-Object { 
    $_.ProcessName -match 'HP|Dell|Lenovo|Alien|Touchpoint|SupportAssist|WolfSecurity' 
} | Select-Object ProcessName, Id, @{N='MemMB';E={[math]::Round($_.WorkingSet64/1MB,1)}}
if ($oemProcs) { $oemProcs | Format-Table -AutoSize } else { Write-Host "  None running" }

# --- Heavy Startup Items ---

Write-Host ""
Write-Host "--- Startup Items ---" -ForegroundColor Yellow
$startupReg = @()
$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($p in $paths) {
    $items = Get-ItemProperty $p -EA SilentlyContinue
    if ($items) {
        $items.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $startupReg += [PSCustomObject]@{
                Location = $p -replace 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\', 'HKLM\..\' -replace 'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\', 'HKCU\..\' -replace 'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\', 'HKLM\WOW64\..'
                Name = $_.Name
                Command = ($_.Value -as [string]).Substring(0, [Math]::Min(80, ($_.Value -as [string]).Length))
            }
        }
    }
}
if ($startupReg) { $startupReg | Format-Table -AutoSize -Wrap } else { Write-Host "  None found" }

# --- Unnecessary AppX Packages ---

Write-Host ""
Write-Host "--- Removable AppX Packages (bloat candidates) ---" -ForegroundColor Yellow
$bloatPatterns = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingFinance',
    'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People',
    'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
    'Microsoft.Xbox*', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
    'Microsoft.YourPhone', 'Microsoft.Todos', 'Microsoft.PowerAutomateDesktop',
    'Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10',  # Cortana
    'Microsoft.WindowsCommunicationsApps', 'Microsoft.SkypeApp',
    'Disney.*', 'SpotifyAB.*', 'BytedancePte.*'  # TikTok etc.
)
$installed = Get-AppxPackage -EA SilentlyContinue | Where-Object {
    $pkg = $_.Name
    $bloatPatterns | Where-Object { $pkg -like $_ }
}
if ($installed) {
    $installed | Select-Object Name, Version | Format-Table -AutoSize
    Write-Host ""
    Write-Host "  To remove: Get-AppxPackage '<Name>' | Remove-AppxPackage" -ForegroundColor Gray
    Write-Host "  To remove for all users (admin): Get-AppxPackage -AllUsers '<Name>' | Remove-AppxPackage -AllUsers" -ForegroundColor Gray
} else {
    Write-Host "  None found (already clean)"
}

# --- Top Memory Consumers ---

Write-Host ""
Write-Host "--- Top 15 Memory Consumers ---" -ForegroundColor Yellow
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 ProcessName, Id, @{N='MemMB';E={[math]::Round($_.WorkingSet64/1MB,1)}} | Format-Table -AutoSize

# --- Services set to Automatic that might not be needed ---

Write-Host ""
Write-Host "--- Suspicious Auto-Start Services (non-Microsoft) ---" -ForegroundColor Yellow
$suspSvc = Get-CimInstance Win32_Service | Where-Object {
    $_.StartMode -eq 'Auto' -and
    $_.PathName -and
    $_.PathName -notmatch 'Windows|Microsoft|svchost|System32' -and
    $_.State -eq 'Running'
} | Select-Object Name, DisplayName, @{N='Path';E={$_.PathName.Substring(0, [Math]::Min(60, $_.PathName.Length))}}
if ($suspSvc) { $suspSvc | Format-Table -AutoSize -Wrap } else { Write-Host "  All clean" }

Write-Host ""
Write-Host "=== Audit Complete ===" -ForegroundColor Cyan
Write-Host "Review above and decide what to kill. Use:" -ForegroundColor Gray
Write-Host "  Stop-Service <name> -Force; Set-Service <name> -StartupType Disabled" -ForegroundColor Gray
Write-Host "  Get-AppxPackage '<name>' | Remove-AppxPackage" -ForegroundColor Gray

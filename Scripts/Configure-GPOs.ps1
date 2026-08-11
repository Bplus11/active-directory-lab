<#
.SYNOPSIS
    Creates and configures 4 of 8 GPOs for MedPoint Health Partners.
.DESCRIPTION
    Handles: GPO-Baseline-Security, GPO-Workstation-Config,
    GPO-Clinical-Restrictions, GPO-LAPS
    
    YOU will create: GPO-IT-Unrestricted, GPO-Drive-Mappings-DWN,
    GPO-Drive-Mappings-WST, GPO-Drive-Mappings-EST
.NOTES
    Run from an elevated PowerShell prompt on the domain controller.
#>

Import-Module GroupPolicy
Import-Module ActiveDirectory

$domain = "bplus.lab"
$base = "OU=_MedPoint,DC=bplus,DC=lab"

# ============================================================
# GPO 1: GPO-Baseline-Security -> linked to _MedPoint (top)
# ============================================================

Write-Host "Creating GPO-Baseline-Security..." -ForegroundColor Cyan

$gpo1 = New-GPO -Name "GPO-Baseline-Security" -Comment "Domain-wide baseline: password, lockout, audit, PS logging"
New-GPLink -Guid $gpo1.Id -Target $base

# Domain password and lockout policy
Set-ADDefaultDomainPasswordPolicy -Identity $domain `
    -MinPasswordLength 12 `
    -ComplexityEnabled $true `
    -MaxPasswordAge "90.00:00:00" `
    -MinPasswordAge "1.00:00:00" `
    -PasswordHistoryCount 24 `
    -LockoutThreshold 5 `
    -LockoutDuration "00:30:00" `
    -LockoutObservationWindow "00:30:00"

# PowerShell script block logging
Set-GPRegistryValue -Name "GPO-Baseline-Security" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
    -ValueName "EnableScriptBlockLogging" `
    -Type DWord `
    -Value 1

# PowerShell module logging
Set-GPRegistryValue -Name "GPO-Baseline-Security" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" `
    -ValueName "EnableModuleLogging" `
    -Type DWord `
    -Value 1

# Audit policies
$auditCategories = @(
    "Logon", "Account Lockout", "Logoff",
    "User Account Management", "Security Group Management",
    "Computer Account Management", "Process Creation",
    "Directory Service Changes"
)
foreach ($cat in $auditCategories) {
    auditpol /set /subcategory:"$cat" /success:enable /failure:enable | Out-Null
}

Write-Host "  DONE: Linked to $base" -ForegroundColor Green
Write-Host "  - Password policy: 12 char min, complexity, 90-day max" -ForegroundColor Gray
Write-Host "  - Lockout: 5 attempts, 30 min duration" -ForegroundColor Gray
Write-Host "  - PowerShell logging enabled" -ForegroundColor Gray
Write-Host "  - Audit policies configured" -ForegroundColor Gray

# ============================================================
# GPO 2: GPO-Workstation-Config -> linked to Workstations OU
# ============================================================

Write-Host "`nCreating GPO-Workstation-Config..." -ForegroundColor Cyan

$gpo2 = New-GPO -Name "GPO-Workstation-Config" -Comment "Workstation lockdown: auto-lock, USB, cmd restrictions"
New-GPLink -Guid $gpo2.Id -Target "OU=Workstations,OU=Computers,$base"

# Inactivity timeout - 600 seconds (10 minutes)
Set-GPRegistryValue -Name "GPO-Workstation-Config" `
    -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "InactivityTimeoutSecs" `
    -Type DWord `
    -Value 600

# Disable USB storage devices
Set-GPRegistryValue -Name "GPO-Workstation-Config" `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR" `
    -ValueName "Start" `
    -Type DWord `
    -Value 4

# Disable cmd.exe (IT override GPO will re-enable for IT users)
Set-GPRegistryValue -Name "GPO-Workstation-Config" `
    -Key "HKCU\SOFTWARE\Policies\Microsoft\Windows\System" `
    -ValueName "DisableCMD" `
    -Type DWord `
    -Value 1

Write-Host "  DONE: Linked to Workstations OU" -ForegroundColor Green
Write-Host "  - 10 min inactivity lock" -ForegroundColor Gray
Write-Host "  - USB storage disabled" -ForegroundColor Gray
Write-Host "  - cmd.exe blocked (IT override will re-enable)" -ForegroundColor Gray

# ============================================================
# GPO 3: GPO-Clinical-Restrictions -> linked to Clinical OU
# ============================================================

Write-Host "`nCreating GPO-Clinical-Restrictions..." -ForegroundColor Cyan

$gpo3 = New-GPO -Name "GPO-Clinical-Restrictions" -Comment "HIPAA-aligned: screensaver, Control Panel, lockdown"
New-GPLink -Guid $gpo3.Id -Target "OU=Clinical,OU=Users,$base"

# Screensaver enabled
Set-GPRegistryValue -Name "GPO-Clinical-Restrictions" `
    -Key "HKCU\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaveActive" `
    -Type String `
    -Value "1"

# Screensaver requires password
Set-GPRegistryValue -Name "GPO-Clinical-Restrictions" `
    -Key "HKCU\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaverIsSecure" `
    -Type String `
    -Value "1"

# Screensaver timeout - 900 seconds (15 minutes)
Set-GPRegistryValue -Name "GPO-Clinical-Restrictions" `
    -Key "HKCU\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaveTimeOut" `
    -Type String `
    -Value "900"

# Block Control Panel access
Set-GPRegistryValue -Name "GPO-Clinical-Restrictions" `
    -Key "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoControlPanel" `
    -Type DWord `
    -Value 1

Write-Host "  DONE: Linked to Clinical OU" -ForegroundColor Green
Write-Host "  - 15 min screensaver with password lock" -ForegroundColor Gray
Write-Host "  - Control Panel access blocked" -ForegroundColor Gray

# ============================================================
# GPO 4: GPO-LAPS -> linked to _MedPoint (top)
# ============================================================

Write-Host "`nCreating GPO-LAPS..." -ForegroundColor Cyan

$gpo4 = New-GPO -Name "GPO-LAPS" -Comment "Local Administrator Password Solution deployment"
New-GPLink -Guid $gpo4.Id -Target $base

Write-Host "  DONE: Linked to $base" -ForegroundColor Green
Write-Host "  - GPO created and linked but LAPS requires manual setup:" -ForegroundColor Yellow
Write-Host "    1. Install LAPS: Get-WindowsCapability -Online | Where Name -like *LAPS*" -ForegroundColor Yellow
Write-Host "    2. Then configure via gpmc.msc:" -ForegroundColor Yellow
Write-Host "       Computer Config > Admin Templates > LAPS" -ForegroundColor Yellow
Write-Host "       - Enable local admin password management" -ForegroundColor Yellow
Write-Host "       - Set password complexity and rotation" -ForegroundColor Yellow
Write-Host "       - Grant SG-IT-Admins read access to passwords" -ForegroundColor Yellow

# ============================================================
# YOUR TURN
# ============================================================

Write-Host "`n===== Script Complete =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "Now create the remaining 4 GPOs yourself." -ForegroundColor White
Write-Host "Instructions are in the YOUR-TURN-GPOs.md file." -ForegroundColor White
Write-Host ""
Write-Host "When finished, verify with:" -ForegroundColor White
Write-Host '  Get-GPO -All | Select DisplayName, GpoStatus | Format-Table' -ForegroundColor Gray

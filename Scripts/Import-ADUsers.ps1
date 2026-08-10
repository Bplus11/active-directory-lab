<#
.SYNOPSIS
    Bulk-creates AD users from a CSV file for MedPoint Health Partners.
.DESCRIPTION
    Reads users.csv, creates AD user accounts in the specified OUs,
    sets attributes, and adds users to security groups.
.NOTES
    Run from an elevated PowerShell prompt on the domain controller.
    Requires the ActiveDirectory module.
#>

param(
    [string]$CsvPath = ".\users.csv",
    [string]$DefaultPassword = "MedP0int2024!",
    [string]$LogPath = ".\user-import-log.txt"
)

Import-Module ActiveDirectory

$users = Import-Csv -Path $CsvPath
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$securePass = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
$created = 0
$skipped = 0
$errors = 0

Add-Content -Path $LogPath -Value "===== Import started: $timestamp ====="

foreach ($user in $users) {
    $sam = $user.Username
    $upn = "$sam@bplus.lab"
    $displayName = "$($user.FirstName) $($user.LastName)"

    # Check if user already exists
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $msg = "SKIPPED: $sam already exists"
        Write-Warning $msg
        Add-Content -Path $LogPath -Value $msg
        $skipped++
        continue
    }

    try {
        # Create the user
        New-ADUser `
            -Name $displayName `
            -GivenName $user.FirstName `
            -Surname $user.LastName `
            -SamAccountName $sam `
            -UserPrincipalName $upn `
            -Path $user.OU `
            -AccountPassword $securePass `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -Title $user.Title `
            -Department $user.Department `
            -Office "$($user.Site) Clinic" `
            -Company "MedPoint Health Partners" `
            -Description "$($user.Title) - $($user.Site)"

        # Add to security groups
        if ($user.Groups) {
            $groupList = $user.Groups -split ";"
            foreach ($group in $groupList) {
                try {
                    Add-ADGroupMember -Identity $group.Trim() -Members $sam
                } catch {
                    $msg = "WARNING: Could not add $sam to group $group - $($_.Exception.Message)"
                    Write-Warning $msg
                    Add-Content -Path $LogPath -Value $msg
                }
            }
        }

        $msg = "CREATED: $sam ($displayName) in $($user.OU)"
        Write-Host $msg -ForegroundColor Green
        Add-Content -Path $LogPath -Value $msg
        $created++

    } catch {
        $msg = "ERROR: Failed to create $sam - $($_.Exception.Message)"
        Write-Error $msg
        Add-Content -Path $LogPath -Value $msg
        $errors++
    }
}

Write-Host "===== Import Complete =====" -ForegroundColor Cyan
Write-Host "Created: $created | Skipped: $skipped | Errors: $errors"
Add-Content -Path $LogPath -Value "===== Import complete: Created=$created Skipped=$skipped Errors=$errors ====="

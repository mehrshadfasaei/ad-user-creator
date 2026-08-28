# New-ADUsersFromCSV.ps1
#
# Creates AD users in bulk from a CSV file instead of doing it one by one in ADUC.
# Give it a CSV with name/OU/groups info, it makes the accounts, sets a random
# temp password, forces a password change at first logon, and logs everything.
#
# Usage:
#   .\New-ADUsersFromCSV.ps1 -CsvPath .\sample-users.csv -WhatIf   # dry run first!
#   .\New-ADUsersFromCSV.ps1 -CsvPath .\sample-users.csv           # actually run it
#
# CSV columns: FirstName,LastName,SamAccountName,OU,Groups,JobTitle,Department
# (Groups separated by ; if more than one, e.g. IT-Staff;VPN-Users)
#
# Requires the ActiveDirectory module (RSAT) and rights to create objects in the target OUs.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [string]$LogPath = ".\ad-user-creator-log.csv",
    [string]$DefaultDomain = $env:USERDNSDOMAIN
)

Import-Module ActiveDirectory -ErrorAction Stop

$results = New-Object System.Collections.Generic.List[Object]

# builds a 12-char password that passes default AD complexity rules
# (skips ambiguous chars like I/O/l/0/1 so it's readable when handed over)
function New-RandomPassword {
    param([int]$Length = 12)

    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghijkmnpqrstuvwxyz'
    $digits  = '23456789'
    $special = '!@#$%^&*'
    $all     = $upper + $lower + $digits + $special

    # guarantee at least one of each type first
    $chars = @(
        $upper[(Get-Random -Maximum $upper.Length)]
        $lower[(Get-Random -Maximum $lower.Length)]
        $digits[(Get-Random -Maximum $digits.Length)]
        $special[(Get-Random -Maximum $special.Length)]
    )

    while ($chars.Count -lt $Length) {
        $chars += $all[(Get-Random -Maximum $all.Length)]
    }

    -join ($chars | Sort-Object { Get-Random })  # shuffle so it's not always Upper-Lower-Digit-Special...
}

$users = Import-Csv -Path $CsvPath

foreach ($user in $users) {

    $displayName = "$($user.FirstName) $($user.LastName)"
    $sam = $user.SamAccountName
    $ou  = $user.OU

    $groups = @()
    if ($user.Groups) {
        $groups = $user.Groups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    $record = [PSCustomObject]@{
        SamAccountName = $sam
        DisplayName    = $displayName
        OU             = $ou
        Status         = ''
        Detail         = ''
        TempPassword   = ''
    }

    try {
        # don't blow up if the account is already there, just skip it
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
            $record.Status = 'Skipped'
            $record.Detail = 'Account already exists'
            Write-Warning "$sam already exists, skipping"
            $results.Add($record)
            continue
        }

        # same for a bad/missing OU - fail this one user, keep going with the rest
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue)) {
            $record.Status = 'Failed'
            $record.Detail = "OU not found: $ou"
            Write-Error "$sam - target OU not found: $ou"
            $results.Add($record)
            continue
        }

        $tempPassword = New-RandomPassword
        $securePwd    = ConvertTo-SecureString $tempPassword -AsPlainText -Force
        $upn          = "$sam@$DefaultDomain"

        if ($PSCmdlet.ShouldProcess($sam, "Create AD user in $ou")) {

            New-ADUser `
                -Name $displayName `
                -GivenName $user.FirstName `
                -Surname $user.LastName `
                -SamAccountName $sam `
                -UserPrincipalName $upn `
                -Path $ou `
                -Title $user.JobTitle `
                -Department $user.Department `
                -AccountPassword $securePwd `
                -ChangePasswordAtLogon $true `
                -Enabled $true

            foreach ($group in $groups) {
                try {
                    Add-ADGroupMember -Identity $group -Members $sam -ErrorAction Stop
                } catch {
                    # user still got created, just flag the group issue and move on
                    Write-Warning "$sam created, but couldn't add to group '$group': $($_.Exception.Message)"
                }
            }

            $record.Status = 'Created'
            $record.Detail = if ($groups.Count -gt 0) { "Groups: $($groups -join ', ')" } else { 'No groups given' }
            $record.TempPassword = $tempPassword
            Write-Host "$sam created" -ForegroundColor Green

        } else {
            $record.Status = 'WhatIf'
            $record.Detail = 'Dry run, nothing changed'
        }

    } catch {
        $record.Status = 'Failed'
        $record.Detail = $_.Exception.Message
        Write-Error "$sam failed: $($_.Exception.Message)"
    }

    $results.Add($record)
}

$results | Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8

$created = ($results | Where-Object Status -eq 'Created').Count
$skipped = ($results | Where-Object Status -eq 'Skipped').Count
$failed  = ($results | Where-Object Status -eq 'Failed').Count

Write-Host ""
Write-Host "Created: $created  Skipped: $skipped  Failed: $failed"
Write-Host "Log: $LogPath"

if ($created -gt 0) {
    Write-Host "Temp passwords are in the log file - hand them out securely and clean up the log after." -ForegroundColor Yellow
}

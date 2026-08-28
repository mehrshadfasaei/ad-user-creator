# AD User Creator

Small PowerShell script for bulk-creating Active Directory users from a CSV, instead of clicking through ADUC one by one.

## What it does

- Reads users from a CSV (name, OU, groups, job title, department)
- Skips accounts that already exist
- Checks the target OU actually exists before trying to create anything in it
- Generates a random temp password (meets standard AD complexity rules)
- Forces a password change at first logon
- Adds the account to the groups listed
- Logs every result to a CSV (created / skipped / failed), including temp passwords

## Requirements

- ActiveDirectory PowerShell module (RSAT)
- Permission to create objects in the target OUs

## Usage

CSV format (see `sample-users.csv`):

```csv
FirstName,LastName,SamAccountName,OU,Groups,JobTitle,Department
Ali,Rezaei,ali.rezaei,"OU=Employees,OU=Tehran,DC=company,DC=local",IT-Staff;VPN-Users,Network Technician,IT
```

Always dry-run first:

```powershell
.\New-ADUsersFromCSV.ps1 -CsvPath .\sample-users.csv -WhatIf
```

Then run for real:

```powershell
.\New-ADUsersFromCSV.ps1 -CsvPath .\sample-users.csv
```

Check `ad-user-creator-log.csv` afterward for temp passwords and anything that failed or got skipped.

## Note

Temp passwords are written in plain text to the log so they can be handed to new hires - treat that file as sensitive and delete it once you're done with it.

Built this after doing onboarding manually a few too many times and getting tired of it.

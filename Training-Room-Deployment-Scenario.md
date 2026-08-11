# Training Room Deployment Scenario
## MedPoint Health Partners — EHR Training Site Setup

### Background

MKS2 Technologies has been contracted to deliver a two-week EHR training program at MedPoint Health Partners' Downtown Clinic. As the Senior Installation Field Engineer, you are responsible for setting up the training environment: 10 laptops provided by MKS2, connected to MedPoint's existing Active Directory environment, configured for training use, and ready for Day 1.

MedPoint's IT team (Kevin Mitchell, Systems Administrator) has given you:
- A network drop in Conference Room B with access to VLAN 30 (the existing AD/lab network)
- Domain admin credentials for training provisioning
- The MedPoint device naming convention documentation
- A list of 20 trainees across clinical departments who will attend in two groups of 10

Your job is to:
1. Provision the training laptops into MedPoint's AD
2. Create training-specific accounts and a security group
3. Create a Training OU and GPO to lock down the training machines
4. Verify network connectivity and domain join for all 10 laptops
5. Validate that trainees can log in and access the EHR training application
6. Document the deployment for the client handoff

---

## Phase 1: Prepare Active Directory for Training

### 1.1 Create the Training OU Structure

The training environment needs its own space in AD — you don't want training objects mixed in with production. Add a Training OU under _MedPoint with sub-OUs for users and computers.

**Do this in the GUI (ADUC):**

Open `dsa.msc`, right-click `_MedPoint`, create:

```
_MedPoint
└── Training
    ├── Training Users
    └── Training Computers
```

Enable accidental deletion protection on each OU.

**Then verify via PowerShell:**

```powershell
Get-ADOrganizationalUnit -SearchBase "OU=Training,OU=_MedPoint,DC=bplus,DC=lab" -Filter * | Select Name, DistinguishedName
```

---

### 1.2 Create Training User Accounts

The 20 trainees need temporary training accounts. These are separate from their production accounts — training accounts have limited permissions and will be disabled after the training concludes.

**Create a CSV file called `training-users.csv`:**

```
FirstName,LastName,Username,Department,Title,Site,OU
Sarah,Chen,t.schen,Training,EHR Training - Physicians,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
James,Rivera,t.jrivera,Training,EHR Training - Physicians,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Maria,Santos,t.msantos,Training,EHR Training - Nursing,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
David,Kim,t.dkim,Training,EHR Training - Nursing,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Ashley,Johnson,t.ajohnson,Training,EHR Training - Medical Assistants,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Robert,Williams,t.rwilliams,Training,EHR Training - Lab,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Emily,Carter,t.ecarter,Training,EHR Training - Pharmacy,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Lisa,Thompson,t.lthompson,Training,EHR Training - Front Desk,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Mark,Anderson,t.manderson,Training,EHR Training - Billing,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Kevin,Mitchell,t.kmitchell,Training,EHR Training - IT,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Rachel,Foster,t.rfoster,Training,EHR Training - Nursing,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Terrence,Washington,t.twashington,Training,EHR Training - Nursing,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Brittany,Cole,t.bcole,Training,EHR Training - Medical Assistants,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Ingrid,Johansson,t.ijohansson,Training,EHR Training - Lab,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Brian,Kessler,t.bkessler,Training,EHR Training - Pharmacy,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Christina,Lane,t.clane,Training,EHR Training - Front Desk,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Veronica,Estrada,t.vestrada,Training,EHR Training - Billing,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Jennifer,Davis,t.jdavis,Training,EHR Training - HR,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Patricia,Moore,t.pmoore,Training,EHR Training - Executive,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
Tanya,Reeves,t.treeves,Training,EHR Training - IT,Downtown,"OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
```

**Note the naming convention:** Training usernames are prefixed with `t.` to immediately distinguish them from production accounts. This is a common practice when deploying temporary accounts into a client's existing AD — it prevents collisions and makes cleanup easy.

**Write an import script** (or modify your existing `Import-ADUsers.ps1`) to import these users. Key differences from the production import:
- All accounts go into the Training Users OU
- Set a common training password (e.g., `Training2024!`)
- Set `-ChangePasswordAtLogon $false` — trainees shouldn't deal with password changes during a training session
- Set an account expiration date so accounts auto-disable after training ends:
  `-AccountExpirationDate (Get-Date).AddDays(14)`

---

### 1.3 Create the Training Security Group

```powershell
New-ADGroup -Name "SG-Training-EHR" `
    -GroupScope Global `
    -GroupCategory Security `
    -Path "OU=Training,OU=_MedPoint,DC=bplus,DC=lab" `
    -Description "EHR training participants - temporary access"
```

Add all training users to the group:

```powershell
Get-ADUser -SearchBase "OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab" -Filter * | ForEach-Object {
    Add-ADGroupMember -Identity "SG-Training-EHR" -Members $_.SamAccountName
}
```

---

## Phase 2: Provision the Training Laptops

### 2.1 Pre-stage Computer Accounts

The 10 MKS2-provided laptops need computer accounts in the Training Computers OU. Use the MedPoint naming convention adapted for training devices: `MP-LT-TRN-[##]`

**Write this one yourself — either a quick loop or individual commands:**

Hint:
```
Name pattern:    MP-LT-TRN-01 through MP-LT-TRN-10
Target OU:       OU=Training Computers,OU=Training,OU=_MedPoint,DC=bplus,DC=lab
Description:     MKS2 training laptop - Downtown EHR Training
```

### 2.2 Image and Configure Each Laptop

In the real deployment, each laptop would need:

1. **Verify/apply the client's standard image** — in a VA deployment, this means confirming the VA Gold Image is current. For this scenario, assume MedPoint has provided a base Windows 10/11 image.

2. **Install VirtIO or hardware-specific drivers** — ensure network adapters are recognized (you already experienced this when the VM had no network adapter without VirtIO drivers — same concept applies to physical hardware with missing NIC drivers).

3. **Set a static IP or configure DHCP** — for a training room, DHCP is typical since laptops move between sites. Ensure the DHCP scope on VLAN 30 has enough leases for the training devices.

4. **Join to the domain** — use the pre-staged computer account name:

```powershell
Add-Computer -DomainName "bplus.lab" -NewName "MP-LT-TRN-01" -OUPath "OU=Training Computers,OU=Training,OU=_MedPoint,DC=bplus,DC=lab" -Credential (Get-Credential) -Restart
```

5. **Verify domain join:**

```powershell
# After reboot, confirm domain membership
systeminfo | findstr /B "Domain"

# Confirm the computer object landed in the right OU
# (run from the DC)
Get-ADComputer "MP-LT-TRN-01" | Select Name, DistinguishedName
```

6. **Install peripherals** — for each training seat: external monitor (if applicable), mouse, keyboard, power adapter. Verify all are functional.

---

## Phase 3: Training Room GPO

### 3.1 Create and Link GPO-Training-Lockdown

Training workstations need tighter restrictions than standard workstations. Trainees should only be able to run the EHR training application — they shouldn't be browsing the web, installing software, or accessing production data.

**Create and link via CLI:**

```powershell
New-GPO -Name "GPO-Training-Lockdown" -Comment "Training laptop restrictions - EHR training sessions" | New-GPLink -Target "OU=Training Computers,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
```

**Configure these settings (mix of CLI and GUI — your choice on method):**

| Setting | Value | Why |
|---------|-------|-----|
| Disable USB storage | USBSTOR Start = 4 | Prevent data exfiltration from training environment |
| Disable Control Panel | NoControlPanel = 1 | Trainees shouldn't modify system settings |
| Disable cmd.exe | DisableCMD = 1 | No command line access for trainees |
| Screen lock timeout | 10 minutes | Training rooms are shared spaces |
| Disable Windows Store | RemoveWindowsStore = 1 | No app installations |
| Hide local drives | NoDrives = 67108863 | Trainees only need the EHR application, not file system access |
| Restrict logon locally | Allow only: SG-Training-EHR, SG-IT-Admins | Only training accounts and IT support can log in |

**The "Restrict logon locally" setting is important** — it ensures that even if a production user wanders up to a training laptop, they can't log in with their regular credentials. This is done in the GUI:

1. Edit GPO-Training-Lockdown in `gpmc.msc`
2. Computer Config → Policies → Windows Settings → Security Settings → Local Policies → User Rights Assignment
3. **Allow log on locally** → add `SG-Training-EHR` and `SG-IT-Admins`

---

## Phase 4: Validation Checklist

Before Day 1, walk every training seat and verify:

```powershell
# Run on each training laptop after domain join and GPO application
# Force a GPO refresh first
gpupdate /force

# Verify domain membership
systeminfo | findstr "Domain"

# Verify GPO is applied
gpresult /r

# Verify network connectivity
ping 192.168.30.1
ping 8.8.8.8
nslookup bplus.lab

# Verify the training user can log in
# (log out of admin, log in as t.schen with training password)
```

**Physical checklist per seat:**
- [ ] Laptop powered on and at login screen
- [ ] External peripherals connected and functional
- [ ] Network cable connected (or Wi-Fi configured)
- [ ] Training user login tested
- [ ] EHR training application accessible
- [ ] Laptop label matches AD computer name (MP-LT-TRN-XX)

---

## Phase 5: The Complication

### Scenario: Half the Training Laptops Won't Apply GPOs

You've joined all 10 laptops to the domain. Five of them are applying GPO-Training-Lockdown correctly — USB is disabled, Control Panel is hidden, everything is locked down. The other five are getting domain-joined successfully but the training GPO isn't applying. Trainees on those machines have full Control Panel access and can open cmd.exe.

### Diagnosis:

**Step 1 — Check where the computer objects actually landed:**

```powershell
# Run from the DC
Get-ADComputer -Filter "Name -like 'MP-LT-TRN*'" | Select Name, DistinguishedName | Sort Name
```

You discover that 5 of the laptops landed in `CN=Computers,DC=bplus,DC=lab` (the default container) instead of `OU=Training Computers,OU=Training,OU=_MedPoint,DC=bplus,DC=lab`.

**Why it happened:** When you ran `Add-Computer` on those 5 machines, the `-OUPath` parameter had a typo, or the pre-staged computer account names didn't match exactly (computer names are case-insensitive but must match character-for-character). If the name in `-NewName` doesn't match an existing pre-staged account, Windows creates a new computer object in the default container instead of using the pre-staged one.

**Step 2 — Verify with:**

```powershell
# Check the default Computers container
Get-ADComputer -SearchBase "CN=Computers,DC=bplus,DC=lab" -Filter "Name -like 'MP-LT-TRN*'" | Select Name
```

Sure enough, five machines are there.

**Step 3 — Fix it:**

Move the misplaced computer objects to the correct OU:

```powershell
Get-ADComputer -SearchBase "CN=Computers,DC=bplus,DC=lab" -Filter "Name -like 'MP-LT-TRN*'" | Move-ADObject -TargetPath "OU=Training Computers,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
```

Then force a GPO refresh on the affected laptops:

```powershell
# From each affected laptop
gpupdate /force

# Or remotely if PS remoting is enabled
Invoke-GPUpdate -Computer "MP-LT-TRN-03" -Force
```

**Step 4 — Prevent it next time:**

Redirect the default computer container so future domain joins land somewhere manageable:

```powershell
redircmp "OU=Training Computers,OU=Training,OU=_MedPoint,DC=bplus,DC=lab"
```

Or better yet, verify pre-staged account names match exactly before joining.

### Why this is a strong interview story:

- It's a realistic deployment problem — computer objects landing in the wrong container is one of the most common AD deployment issues
- You diagnosed it methodically: noticed the GPO wasn't applying, checked where the objects actually were, identified the root cause, fixed it, and implemented a preventive measure
- It shows you understand GPO scoping — GPOs linked to an OU don't affect objects in the default CN=Computers container because it's not an OU
- The fix (`Move-ADObject` + `gpupdate /force`) is exactly what you'd do at a VA training site
- The prevention (`redircmp`) shows you think about the next deployment, not just the current fire

---

## Phase 6: Post-Training Cleanup

After the two-week training concludes, clean up the training objects:

```powershell
# Disable all training accounts (don't delete — keep for audit trail)
Get-ADUser -SearchBase "OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab" -Filter * | Disable-ADAccount

# Disable training computer accounts
Get-ADComputer -SearchBase "OU=Training Computers,OU=Training,OU=_MedPoint,DC=bplus,DC=lab" -Filter * | Disable-ADAccount

# Generate a summary report for client handoff
$users = Get-ADUser -SearchBase "OU=Training Users,OU=Training,OU=_MedPoint,DC=bplus,DC=lab" -Filter * -Properties Created, AccountExpirationDate, Enabled | Select Name, SamAccountName, Created, AccountExpirationDate, Enabled
$users | Export-Csv "C:\Scripts\Training-Cleanup-Report.csv" -NoTypeInformation

Write-Host "Training cleanup complete. $($users.Count) accounts disabled." -ForegroundColor Green
```

Provide the cleanup report to MedPoint's IT team as part of the client handoff. This documents what was created, when, and confirms everything has been disabled — important for compliance in a healthcare environment.

# Your Turn: Build These 4 GPOs

The script handled GPO-Baseline-Security, GPO-Workstation-Config, GPO-Clinical-Restrictions, and GPO-LAPS. Now you're building the remaining four.

---

## GPO 5: GPO-IT-Unrestricted

**Target OU:** `OU=IT,OU=Users,OU=_MedPoint,DC=bplus,DC=lab`

### Step 1 — Create and link (CLI)

Use the pipe trick to create and link in one shot:

```powershell
New-GPO -Name "GPO-IT-Unrestricted" -Comment "IT staff: full access, local admin" | New-GPLink -Target "OU=IT,OU=Users,OU=_MedPoint,DC=bplus,DC=lab"
```

That pipe sends the newly created GPO object directly into `New-GPLink` — it pulls the GUID automatically. One line, no variables needed.

### Step 2 — Re-enable cmd.exe for IT (CLI)

The workstation GPO blocks cmd.exe domain-wide. This GPO overrides that for IT users. Use `Set-GPRegistryValue` with the same registry key but set the value to 0:

```
Key:       HKCU\SOFTWARE\Policies\Microsoft\Windows\System
ValueName: DisableCMD
Type:      DWord
Value:     0
```

Write the `Set-GPRegistryValue` command yourself — reference the script to see the syntax pattern.

### Step 3 — Re-enable Control Panel for IT (CLI)

Same idea — override the clinical restriction. Same key as the script used:

```
Key:       HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer
ValueName: NoControlPanel
Type:      DWord
Value:     0
```

### Step 4 — Add IT admins to local Administrators group (GUI)

This one can only be done in the Group Policy Editor:

1. Open `gpmc.msc`
2. Find GPO-IT-Unrestricted, right-click it, click **Edit**
3. Navigate: **Computer Configuration → Policies → Windows Settings → Security Settings → Restricted Groups**
4. Right-click Restricted Groups → **Add Group**
5. Type `SG-IT-Admins` → OK
6. Click **"This group is a member of"** → Add → type `Administrators` → OK
7. Close the editor

This tells every computer that processes this GPO to add SG-IT-Admins to the local Administrators group.

---

## GPO 6: GPO-Drive-Mappings-DWN

**Target OU:** `OU=Downtown,OU=Workstations,OU=Computers,OU=_MedPoint,DC=bplus,DC=lab`

### Step 1 — Create and link (CLI)

Same one-liner pattern as GPO 5. Write it yourself — just change the name, comment, and target OU.

### Step 2 — Configure drive mappings (GUI only)

Group Policy Preferences drive maps cannot be set via PowerShell. This is one of those things you'll always do in the editor.

1. Open `gpmc.msc`, find GPO-Drive-Mappings-DWN, right-click → **Edit**
2. Navigate: **User Configuration → Preferences → Windows Settings → Drive Maps**
3. Right-click in the right pane → **New → Mapped Drive**

**S: drive (clinical shared drive)**
- Action: **Create**
- Location: `\\DC01\ClinicalShare$` (or whatever UNC path you want — the share doesn't need to exist for the GPO to be configured)
- Check **Reconnect**
- Drive Letter: Use → **S:**

**H: drive (user home folder)**
- Action: **Create**
- Location: `\\DC01\Home$\%USERNAME%`
- Check **Reconnect**
- Drive Letter: Use → **H:**

### Step 3 — Deploy printers (GUI)

1. Still in the GPO editor, navigate: **User Configuration → Preferences → Control Panel Settings → Printers**
2. Right-click → **New → Shared Printer**
3. Action: **Create**
4. Share path: `\\DC01\MP-PRN-DWN-01`
5. Optionally check **Set this printer as the default printer** for the first one
6. Repeat for any other Downtown printers (MP-PRN-DWN-02 through 05)

---

## GPO 7: GPO-Drive-Mappings-WST

**Target OU:** `OU=WestSide,OU=Workstations,OU=Computers,OU=_MedPoint,DC=bplus,DC=lab`

Same process as GPO 6. Create and link via CLI, then configure in the GUI:

- Same S: and H: drive mappings (the share paths are the same, only the printers differ)
- Deploy WestSide printers: `\\DC01\MP-PRN-WST-01` through `\\DC01\MP-PRN-WST-04`

---

## GPO 8: GPO-Drive-Mappings-EST

**Target OU:** `OU=EastSide,OU=Workstations,OU=Computers,OU=_MedPoint,DC=bplus,DC=lab`

Same process again:

- Same S: and H: drive mappings
- Deploy EastSide printers: `\\DC01\MP-PRN-EST-01` through `\\DC01\MP-PRN-EST-03`

---

## Verify Everything When Done

After all 4 are created, run these to confirm:

```powershell
# List all GPOs — you should see all 8
Get-GPO -All | Select DisplayName, GpoStatus | Format-Table

# Check what's linked to the _MedPoint OU tree
Get-GPInheritance -Target "OU=_MedPoint,DC=bplus,DC=lab"

# Check a specific OU to see which GPOs apply
Get-GPInheritance -Target "OU=IT,OU=Users,OU=_MedPoint,DC=bplus,DC=lab"

# See all settings in a specific GPO (generates an HTML report)
Get-GPOReport -Name "GPO-IT-Unrestricted" -ReportType Html -Path "C:\Scripts\GPO-IT-Report.html"
```

The HTML report is especially useful — open it in a browser and you can see every setting configured in the GPO, which is a great way to verify your work.

---

## How GPO Precedence Works (Why This All Fits Together)

GPOs process in this order: **L-S-D-OU** (Local → Site → Domain → OU). Within OUs, child OUs process after parent OUs, so child settings win.

For an IT user logging into a Downtown workstation:

1. **GPO-Baseline-Security** applies (linked to _MedPoint, the parent)
2. **GPO-Workstation-Config** applies (linked to Workstations) — blocks cmd.exe
3. **GPO-Drive-Mappings-DWN** applies (linked to Downtown) — maps drives
4. **GPO-Clinical-Restrictions** does NOT apply — it's linked to Users → Clinical, not to IT
5. **GPO-IT-Unrestricted** applies (linked to Users → IT) — re-enables cmd.exe

The IT GPO wins over the Workstation GPO for cmd.exe because user policies from a more specific OU override broader computer policies. This is called the "last writer wins" principle in GPO processing.

For a nurse logging into the same Downtown workstation:

1. GPO-Baseline-Security applies
2. GPO-Workstation-Config applies — blocks cmd.exe
3. GPO-Drive-Mappings-DWN applies — maps drives
4. GPO-Clinical-Restrictions applies — locks screensaver, blocks Control Panel
5. GPO-IT-Unrestricted does NOT apply — nurse is not in the IT OU

Same computer, different user experience. That's the power of splitting user and computer policies into separate GPOs linked to separate OUs.

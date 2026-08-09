$grpPath = "OU=Security Groups,OU=Groups,OU=_MedPoint,DC=bplus,DC=lab"

$groups = @(
    "SG-Clinical-AllStaff|Access to clinical shared drives",
    "SG-EHR-Users|Access to EHR application",
    "SG-EHR-Admins|EHR administrative functions",
    "SG-Billing-Access|Billing system and financial data access",
    "SG-PHI-Access|Protected Health Information access",
    "SG-HR-Confidential|HR records and personnel files",
    "SG-IT-Admins|Domain admin-tier access",
    "SG-Workstation-LocalAdmin|Local admin rights on workstations",
    "SG-VPN-Users|Remote access VPN authorization",
    "SG-Printers-Downtown|Downtown clinic printers",
    "SG-Printers-WestSide|West Side clinic printers",
    "SG-Printers-EastSide|East Side clinic printers"
)

foreach ($g in $groups) {
    $name = $g.Split("|")[0]
    $desc = $g.Split("|")[1]
    New-ADGroup -Name $name -GroupScope Global -GroupCategory Security -Path $grpPath -Description $desc
    Write-Host "CREATED: $name" -ForegroundColor Green
}

# Import-ADComputers.ps1
$computers = Import-Csv -Path ".\computers.csv"

foreach ($c in $computers) {
    if (-not (Get-ADComputer -Filter "Name -eq '$($c.ComputerName)'" -ErrorAction SilentlyContinue)) {
        New-ADComputer -Name $c.ComputerName -Path $c.OU -Description $c.Description
        Write-Host "CREATED: $($c.ComputerName)" -ForegroundColor Green
    } else {
        Write-Warning "SKIPPED: $($c.ComputerName) already exists"
    }
}
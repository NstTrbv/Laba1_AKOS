param([switch]$UseVHD)

$Root = "C:\LogsDisk"
$Img  = "C:\logs_disk.vhdx"

if ($UseVHD) {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")
    if (-not $admin) { Write-Host "Запустите PowerShell от имени администратора"; exit 1 }

    New-Item -ItemType Directory -Force $Root | Out-Null
    if (-not (Test-Path $Img)) {
       
        $dp = @"
create vdisk file="$Img" maximum=512 type=expandable
attach vdisk
create partition primary
format fs=ntfs quick label=LOGS
assign mount="$Root"
"@
        $dp | diskpart | Out-Null
    } else {
        Mount-DiskImage -ImagePath $Img -ErrorAction SilentlyContinue | Out-Null
        
    }
} else {
    New-Item -ItemType Directory -Force $Root | Out-Null   
}

foreach ($d in "auth_service","data_process_service","system_event_handler_service") {
    New-Item -ItemType Directory -Force "$Root\LOGS\$d" | Out-Null
}
New-Item -ItemType Directory -Force "$Root\backup" | Out-Null

Write-Host "Готово:"
Get-ChildItem "$Root\LOGS" -Directory | Select-Object Name
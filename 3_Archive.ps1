param(
    [string]$DIR,
    [int]$N = 90,
    [int]$M = 5,
    [string]$BACKUP = "C:\LogsDisk\backup",
    [long]$TOTAL = 0
)

if (-not $DIR -or -not (Test-Path $DIR -PathType Container)) {
    Write-Host "Нет такой папки: $DIR"
    exit 1
}

if (-not $PSBoundParameters.ContainsKey('N')) { $N = [int](Read-Host "Введите порог N (в процентах)") }
if (-not $PSBoundParameters.ContainsKey('M')) { $M = [int](Read-Host "Сколько старых файлов архивировать (M)") }

New-Item -ItemType Directory -Force $BACKUP | Out-Null
$BACKUP = (Resolve-Path $BACKUP).Path

if ($TOTAL -le 0) { $TOTAL = 512MB }

function Get-Size($path) {
    $m = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    return [long]$m.Sum
}

$USED    = Get-Size $DIR
$PERCENT = [long][math]::Floor($USED * 100 / $TOTAL)
Write-Host "Занято $PERCENT% (порог $N%)"

if ($PERCENT -le $N) {
    Write-Host "Порог не превышен, ничего не делаем"
    exit 0
}

$QUOTA = [long][math]::Floor($TOTAL / 3)

foreach ($sub in Get-ChildItem $DIR -Directory) {
    $size = Get-Size $sub.FullName
    Write-Host "$($sub.Name): $size байт (квота $QUOTA)"

    if ($size -gt $QUOTA) {
       
        $files = @(Get-ChildItem $sub.FullName -Filter *.log -File |
                   Sort-Object LastWriteTime |
                   Select-Object -SkipLast 1 |
                   Select-Object -First $M)

        if ($files.Count -gt 0) {
            $archive = Join-Path $BACKUP ("{0}_{1}.zip" -f $sub.Name, (Get-Date -Format "yyyyMMdd_HHmmss"))
            try {
                Compress-Archive -Path $files.FullName -DestinationPath $archive -ErrorAction Stop
                Remove-Item $files.FullName
                Write-Host "  заархивировано: $($files.Count) файлов -> $archive"
            } catch {
                Write-Host "  ошибка архивации"
            }
        }
    }
}
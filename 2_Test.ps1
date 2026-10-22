param([string]$Mode)

$SCRIPT = Join-Path $PSScriptRoot "3_Archive.ps1"
$LOGS   = "C:\LogsDisk\LOGS"
$A = "auth_service"; $B = "data_process_service"; $C = "system_event_handler_service"

Add-Type -AssemblyName System.IO.Compression.FileSystem

function make($root, $name, [int]$count, [long]$kb) {
    $dir = Join-Path $root $name
    New-Item -ItemType Directory -Force $dir | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    for ($i = 1; $i -le $count; $i++) {
        $ts   = $now - ($count - $i) * 86400
        $date = [DateTimeOffset]::FromUnixTimeSeconds($ts).LocalDateTime
        $file = Join-Path $dir ("{0}_{1}_{2}.log" -f $name, $date.ToString("yyyy_MM_dd"), $ts)
        $fs = [IO.File]::Create($file); $fs.SetLength($kb * 1KB); $fs.Close()
        (Get-Item $file).LastWriteTime = $date
    }
}

if ($Mode -eq "create") {
    if (-not (Test-Path $LOGS)) { Write-Host "$LOGS не существует, сначала запустите 1_Mount.ps1"; exit 1 }
    make $LOGS $A 6 102400   
    make $LOGS $B 1 102400   
    make $LOGS $C 1 30720   
    Write-Host "Файлы созданы:"
    Get-ChildItem $LOGS -Recurse -File | Select-Object Directory, Name, @{n='MB';e={$_.Length/1MB}}
    exit 0
}

$TMP   = Join-Path $env:TEMP ("lab1_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $TMP | Out-Null
$TOTAL = 3000 * 1024
$script:ok = 0; $script:bad = 0
$PS = (Get-Process -Id $PID).Path   

function reset { Remove-Item "$TMP\LOGS","$TMP\backup" -Recurse -Force -ErrorAction SilentlyContinue
                 New-Item -ItemType Directory -Force "$TMP\LOGS" | Out-Null }
function run($n, $m) { & $PS -NoProfile -ExecutionPolicy Bypass -File $SCRIPT "$TMP\LOGS" $n $m "$TMP\backup" $TOTAL | Out-Null }
function count($d)   { @(Get-ChildItem "$TMP\LOGS\$d" -File -ErrorAction SilentlyContinue).Count }
function archives()  { @(Get-ChildItem "$TMP\backup\*.zip" -ErrorAction SilentlyContinue).Count }
function check($name, $got, $exp) {
    if ("$got" -eq "$exp") { Write-Host " OK: $name" -ForegroundColor Green; $script:ok++ }
    else { Write-Host " FAIL: $name (получили $got, ожидали $exp)" -ForegroundColor Red; $script:bad++ }
}

Write-Host "Тест 1: порог не превышен, ничего не архивируем"
reset
make "$TMP\LOGS" $A 3 100; make "$TMP\LOGS" $B 2 100; make "$TMP\LOGS" $C 1 100
run 90 5
check "архивов нет" (archives) 0
check "файлы на месте" (count $A) 3

Write-Host "Тест 2: квоту превысила только одна папка"
reset
make "$TMP\LOGS" $A 12 100; make "$TMP\LOGS" $B 5 100; make "$TMP\LOGS" $C 5 100
$sorted = Get-ChildItem "$TMP\LOGS\$A" -File | Sort-Object LastWriteTime
$OLD = $sorted[0].Name; $NEW = $sorted[-1].Name
run 70 5
check "создан один архив" (archives) 1
check "в $A осталось 7 файлов" (count $A) 7
check "$B не тронута" (count $B) 5
check "$C не тронута" (count $C) 5
$zip = (Get-ChildItem "$TMP\backup\*.zip" | Select-Object -First 1).FullName
$z = [IO.Compression.ZipFile]::OpenRead($zip); $zc = $z.Entries.Count; $z.Dispose()
check "в архиве 5 файлов" $zc 5
check "самый старый файл удален" (Test-Path "$TMP\LOGS\$A\$OLD") $false
check "самый новый файл остался" (Test-Path "$TMP\LOGS\$A\$NEW") $true

Write-Host "Тест 3: все три папки превысили квоту"
reset
make "$TMP\LOGS" $A 12 100; make "$TMP\LOGS" $B 12 100; make "$TMP\LOGS" $C 12 100
run 90 5
check "три архива" (archives) 3
check "в $B осталось 7 файлов" (count $B) 7

Write-Host "Тест 4: в папке всего один файл, его не трогаем (в него идет запись)"
reset
make "$TMP\LOGS" $A 1 1200; make "$TMP\LOGS" $B 1 100; make "$TMP\LOGS" $C 1 100
run 40 5
check "архивов нет" (archives) 0
check "файл остался" (count $A) 1

Write-Host "Тест 5: неправильный путь"
& $PS -NoProfile -ExecutionPolicy Bypass -File $SCRIPT "C:\нет\такой\папки" 2>&1 | Out-Null
check "код выхода 1" $LASTEXITCODE 1

Remove-Item $TMP -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Успешно: $($script:ok), ошибок: $($script:bad)"
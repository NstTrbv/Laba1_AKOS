#!/bin/bash
SCRIPT=$(dirname "$(readlink -f "$0")")/3_archive_logs.sh
A=auth_service
B=data_process_service
C=system_event_handler_service

make() {
    dir="$1/$2"
    mkdir -p "$dir"
    now=$(date +%s)
    for i in $(seq 1 $3); do
        ts=$(( now - ($3 - i) * 86400 ))
        file="$dir/$2_$(date -d @$ts +%Y_%m_%d)_$ts.log"
        fallocate -l ${4}K "$file"
        touch -d @$ts "$file"
    done
}

if [ "$1" = "create" ]; then
    if ! mountpoint -q /LOGS; then
        echo "/LOGS не смонтирован, сначала запустите 1_mount_logs.sh"
        exit 1
    fi
    make /LOGS $A 6 102400     #6 файлов по 100 МБ
    make /LOGS $B 1 102400     #1 файл 100 МБ
    make /LOGS $C 1 30720      #1 файл 30 МБ
    echo "Файлы созданы:"
    ls -lh /LOGS/*/
    df -h /LOGS
    exit 0
fi

TMP=$(mktemp -d)
TOTAL=$((3000 * 1024))
ok=0
bad=0

reset() {
    rm -rf "$TMP/LOGS" "$TMP/backup"
    mkdir -p "$TMP/LOGS"
}

run() {
    bash "$SCRIPT" "$TMP/LOGS" $1 $2 "$TMP/backup" $TOTAL > /dev/null
}

count()    { ls "$TMP/LOGS/$1" | wc -l; }
archives() { ls "$TMP/backup"/*.tar.gz 2>/dev/null | wc -l; }

check() {
    if [ "$2" = "$3" ]; then
        echo "  ok: $1"
        ok=$((ok + 1))
    else
        echo "  ОШИБКА: $1 (получили $2, ожидали $3)"
        bad=$((bad + 1))
    fi
}

echo "Тест 1: порог не превышен, ничего не архивируем"
reset
make "$TMP/LOGS" $A 3 100; make "$TMP/LOGS" $B 2 100; make "$TMP/LOGS" $C 1 100
run 90 5
check "архивов нет" "$(archives)" 0
check "файлы на месте" "$(count $A)" 3

echo "Тест 2: квоту превысила только одна папка"
reset
make "$TMP/LOGS" $A 12 100; make "$TMP/LOGS" $B 5 100; make "$TMP/LOGS" $C 5 100
OLD=$(ls -tr "$TMP/LOGS/$A" | head -n 1)     # самый старый файл
NEW=$(ls -tr "$TMP/LOGS/$A" | tail -n 1)     # самый новый файл
run 70 5
check "создан один архив" "$(archives)" 1
check "в $A осталось 7 файлов" "$(count $A)" 7
check "$B не тронута" "$(count $B)" 5
check "$C не тронута" "$(count $C)" 5
check "в архиве 5 файлов" "$(tar -tzf "$TMP"/backup/*.tar.gz | wc -l)" 5
check "самый старый файл удален" "$(ls "$TMP/LOGS/$A/$OLD" 2>/dev/null | wc -l)" 0
check "самый новый файл остался" "$(ls "$TMP/LOGS/$A/$NEW" 2>/dev/null | wc -l)" 1

echo "Тест 3: все три папки превысили квоту"
reset
make "$TMP/LOGS" $A 12 100; make "$TMP/LOGS" $B 12 100; make "$TMP/LOGS" $C 12 100
run 90 5
check "три архива" "$(archives)" 3
check "в $B осталось 7 файлов" "$(count $B)" 7

echo "Тест 4: в папке всего один файл, его не трогаем (в него идет запись)"
reset
make "$TMP/LOGS" $A 1 1200; make "$TMP/LOGS" $B 1 100; make "$TMP/LOGS" $C 1 100
run 40 5
check "архивов нет" "$(archives)" 0
check "файл остался" "$(count $A)" 1

echo "Тест 5: неправильный путь"
bash "$SCRIPT" /нет/такой/папки > /dev/null 2>&1
check "код выхода 1" "$?" 1

rm -rf "$TMP"
echo
echo "Успешно: $ok, ошибок: $bad"

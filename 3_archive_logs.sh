#!/bin/bash
DIR=$1
N=${2:-90}
M=${3:-5}
BACKUP=$(realpath -m "${4:-/backup}")
TOTAL=$5

if [ ! -d "$DIR" ]; then
    echo "Нет такой папки: $DIR"
    exit 1
fi

if [ -z "$2" ]; then
    read -p "Введите порог N (в процентах): " N
fi
if [ -z "$3" ]; then
    read -p "Сколько старых файлов архивировать (M): " M
fi

mkdir -p "$BACKUP"

if [ -z "$TOTAL" ]; then
    TOTAL=$(df -B1 --output=size "$DIR" | tail -n 1 | tr -d ' ')
fi

get_size() {
    find "$1" -type f -printf '%s\n' | awk '{s += $1} END {print s + 0}'
}

USED=$(get_size "$DIR")
PERCENT=$(( USED * 100 / TOTAL ))
echo "Занято $PERCENT% (порог $N%)"

if [ "$PERCENT" -le "$N" ]; then
    echo "Порог не превышен, ничего не делаем"
    exit 0
fi

QUOTA=$(( TOTAL / 3 ))

for sub in "$DIR"/*/; do
    sub=${sub%/}
    size=$(get_size "$sub")
    echo "$(basename "$sub"): $size байт (квота $QUOTA)"

    if [ "$size" -gt "$QUOTA" ]; then
        files=$(cd "$sub" && ls -tr *.log 2>/dev/null | head -n -1 | head -n "$M")

        if [ -n "$files" ]; then
            archive="$BACKUP/$(basename "$sub")_$(date +%Y%m%d_%H%M%S).tar.gz"
            if tar -czf "$archive" -C "$sub" $files; then
                (cd "$sub" && rm $files)
                echo "  заархивировано: $(echo $files | wc -w) файлов -> $archive"
            else
                echo "  ошибка архивации"
            fi
        fi
    fi
done

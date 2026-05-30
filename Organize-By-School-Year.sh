#!/bin/sh
set -eu

ROOT="/volume1/SchoolBoardArchive"
EXECUTE="${EXECUTE:-${APPLY:-0}}"

usage() {
  echo "Usage:"
  echo "  ./Organize-By-School-Year.sh [-r ROOT] [-x]"
  echo
  echo "Default is dry-run."
  echo
  echo "Examples:"
  echo "  ./Organize-By-School-Year.sh"
  echo "  ./Organize-By-School-Year.sh -x"
  echo "  ./Organize-By-School-Year.sh -r /volume1/SchoolBoardArchive -x"
  exit 1
}

while getopts "r:xh" opt; do
  case "$opt" in
    r) ROOT="$OPTARG" ;;
    x) EXECUTE=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

[ -d "$ROOT" ] || { echo "ERROR: root folder does not exist: $ROOT"; exit 1; }

LOG_DIR="$ROOT/#scripts"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
PLAN="$LOG_DIR/root_sort_plan_$RUN_ID.tsv"
MANUAL="$LOG_DIR/root_sort_manual_$RUN_ID.txt"

mkdir -p "$LOG_DIR"
printf 'action\tsource\tevent_date\tdestination\tfile\n' > "$PLAN"
: > "$MANUAL"

if [ "$EXECUTE" -eq 1 ]; then
  echo "MODE: EXECUTE"
else
  echo "MODE: DRY RUN"
fi

echo "ROOT:          $ROOT"
echo "Plan:          $PLAN"
echo "Manual review: $MANUAL"
echo

pad2() {
    n="$(printf '%s' "$1" | sed 's/^0*//')"
    [ -n "$n" ] || n=0
    printf '%02d' "$n"
}

school_dir() {
    y="$1"
    m="$(printf '%s' "$2" | sed 's/^0*//')"
    [ -n "$m" ] || m=0

    if [ "$m" -ge 7 ]; then
        start="$y"
    else
        start=$((y - 1))
    fi

    end=$((start + 1))
    printf '%04d-%04d-school-board\n' "$start" "$end"
}

extract_date() {
    base="$1"

    ymd="$(printf '%s\n' "$base" | grep -Eo '[12][0-9]{3}-[01]?[0-9]-[0-3]?[0-9]' | head -n 1 || true)"
    if [ -n "$ymd" ]; then
        y="${ymd%%-*}"
        rest="${ymd#*-}"
        m="${rest%%-*}"
        d="${rest#*-}"
        mp="$(pad2 "$m")"
        dp="$(pad2 "$d")"
        printf 'name|%s-%s-%s|%s|%s|%s\n' "$y" "$mp" "$dp" "$y" "$mp" "$dp"
        return 0
    fi

	mdy4="$(printf '%s\n' "$base" | grep -Eo '(^|[^0-9])[01]?[0-9]-[0-3]?[0-9]-[12][0-9]{3}([^0-9]|$)' | head -n 1 | sed 's/^[^0-9]//; s/[^0-9]$//' || true)"
    if [ -n "$mdy4" ]; then
        m="${mdy4%%-*}"
        rest="${mdy4#*-}"
        d="${rest%%-*}"
        y="${rest#*-}"
        mp="$(pad2 "$m")"
        dp="$(pad2 "$d")"
        printf 'name|%s-%s-%s|%s|%s|%s\n' "$y" "$mp" "$dp" "$y" "$mp" "$dp"
        return 0
    fi

    mdy="$(printf '%s\n' "$base" | grep -Eo '(^|[^0-9])[01]?[0-9]-[0-3]?[0-9]-[0-9]{2}([^0-9]|$)' | head -n 1 | sed 's/^[^0-9]//; s/[^0-9]$//' || true)"
    if [ -n "$mdy" ]; then
        m="${mdy%%-*}"
        rest="${mdy#*-}"
        d="${rest%%-*}"
        yy="${rest#*-}"
        y=$((2000 + yy))
        mp="$(pad2 "$m")"
        dp="$(pad2 "$d")"
        printf 'name|%s-%s-%s|%s|%s|%s\n' "$y" "$mp" "$dp" "$y" "$mp" "$dp"
        return 0
    fi

    return 1
}

find "$ROOT" -maxdepth 1 -type f | while IFS= read -r f; do
    base="${f##*/}"

    info="$(extract_date "$base" || true)"
    if [ -z "$info" ]; then
        printf '%s\n' "$f" >> "$MANUAL"
        printf 'manual\tno-clear-date\t\t\t%s\n' "$f" >> "$PLAN"
        continue
    fi

    oldIFS="$IFS"
    IFS='|'
    set -- $info
    IFS="$oldIFS"

    source="$1"
    event_date="$2"
    y="$3"
    m="$4"
    folder="$(school_dir "$y" "$m")"
    dest="$ROOT/$folder"

    if [ ! -d "$dest" ]; then
        printf '%s -> missing folder %s\n' "$f" "$dest" >> "$MANUAL"
        printf 'manual\t%s\t%s\t%s\t%s\n' "$source" "$event_date" "$dest" "$f" >> "$PLAN"
        continue
    fi

    if [ "$EXECUTE" -eq 1 ]; then
        if mv -n -- "$f" "$dest/"; then
            printf 'moved\t%s\t%s\t%s\t%s\n' "$source" "$event_date" "$dest" "$f" >> "$PLAN"
        else
            printf '%s -> move failed to %s\n' "$f" "$dest" >> "$MANUAL"
            exit 1
        fi
    else
        printf 'would-move\t%s\t%s\t%s\t%s\n' "$source" "$event_date" "$dest" "$f" >> "$PLAN"
    fi
done

printf 'Plan:          %s\n' "$PLAN"
printf 'Manual review: %s\n' "$MANUAL"

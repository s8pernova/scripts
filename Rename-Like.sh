cat > Rename-Like.sh <<'EOF'
#!/bin/sh
set -eu

ROOT="."
TYPE="d"
EXECUTE=0
OLD=""
NEW=""

usage() {
  echo "Usage:"
  echo "  ./Rename-Like.sh -o OLD -n NEW [-r ROOT] [-t dirs|files|all] [-x]"
  echo
  echo "Default is dry-run and folders only."
  echo
  echo "Examples:"
  echo "  ./Rename-Like.sh -o 'School Board' -n 'sb'"
  echo "  ./Rename-Like.sh -o 'School Board' -n 'sb' -x"
  echo "  ./Rename-Like.sh -o 'School Board' -n 'sb' -t all -x"
  exit 1
}

while getopts "o:n:r:t:xh" opt; do
  case "$opt" in
    o) OLD="$OPTARG" ;;
    n) NEW="$OPTARG" ;;
    r) ROOT="$OPTARG" ;;
    t) TYPE="$OPTARG" ;;
    x) EXECUTE=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

[ -n "$OLD" ] || usage

case "$TYPE" in
  dirs) FIND_TYPE="-type d" ;;
  files) FIND_TYPE="-type f" ;;
  all) FIND_TYPE="" ;;
  *) echo "ERROR: -t must be dirs, files, or all"; exit 1 ;;
esac

if [ "$EXECUTE" -eq 1 ]; then
  echo "MODE: EXECUTE"
else
  echo "MODE: DRY RUN"
fi

echo "ROOT: $ROOT"
echo "OLD:  $OLD"
echo "NEW:  $NEW"
echo

# shellcheck disable=SC2086
find "$ROOT" -depth $FIND_TYPE -name "*$OLD*" \
  -not -path '*/#recycle/*' \
  -not -path '*/@eaDir/*' \
  -exec sh -c '
OLD=$1
NEW=$2
EXECUTE=$3
shift 3

replace_literal() {
  printf "%s" "$1" | awk -v old="$OLD" -v new="$NEW" "
    BEGIN {
      s = ARGV[1]
      ARGV[1] = \"\"
      out = \"\"
      while ((i = index(s, old)) > 0) {
        out = out substr(s, 1, i - 1) new
        s = substr(s, i + length(old))
      }
      print out s
    }
  " "$1"
}

for oldpath do
  dir=${oldpath%/*}
  base=${oldpath##*/}

  [ "$dir" = "$oldpath" ] && dir="."

  newbase=$(replace_literal "$base")
  newpath="$dir/$newbase"

  [ "$oldpath" = "$newpath" ] && continue

  if [ -e "$newpath" ]; then
    echo "SKIP exists: $oldpath -> $newpath"
    continue
  fi

  if [ "$EXECUTE" -eq 1 ]; then
    mv "$oldpath" "$newpath"
    echo "RENAMED: $oldpath -> $newpath"
  else
    echo "WOULD rename: $oldpath -> $newpath"
  fi
done
' sh "$OLD" "$NEW" "$EXECUTE" {} +
EOF

chmod +x Rename-Like.sh
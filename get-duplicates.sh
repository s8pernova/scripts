#!/bin/sh
set -eu

ROOT="."
OUT="duplicates.tsv"
TOL=0
MIN_SIZE=1

usage() {
  echo "Usage:"
  echo "  ./Get-Duplicates.sh [-r ROOT] [-o OUTPUT.tsv] [-b TOLERANCE_BYTES] [-m MIN_SIZE_BYTES]"
  echo
  echo "Defaults:"
  echo "  ROOT=."
  echo "  OUTPUT=duplicates.tsv"
  echo "  TOLERANCE_BYTES=0"
  echo "  MIN_SIZE_BYTES=1"
  echo
  echo "Examples:"
  echo "  ./Get-Duplicates.sh"
  echo "  ./Get-Duplicates.sh -r /volume1/SchoolBoardArchive"
  echo "  ./Get-Duplicates.sh -b 1024 -m 1048576"
  exit 1
}

while getopts "r:o:b:m:h" opt; do
  case "$opt" in
    r) ROOT="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    b) TOL="$OPTARG" ;;
    m) MIN_SIZE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

case "$TOL" in
  ''|*[!0-9]*) echo "ERROR: -b must be a non-negative integer byte count"; exit 1 ;;
esac

case "$MIN_SIZE" in
  ''|*[!0-9]*) echo "ERROR: -m must be a non-negative integer byte count"; exit 1 ;;
esac

[ -d "$ROOT" ] || { echo "ERROR: root folder does not exist: $ROOT"; exit 1; }

TMP="${OUT}.tmp.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

echo "Scanning: $ROOT"
echo "Tolerance bytes: $TOL"
echo "Minimum size bytes: $MIN_SIZE"
echo "Output: $OUT"
echo

find "$ROOT" \
  \( -path '*/#recycle' -o -path '*/#recycle/*' -o -path '*/@eaDir' -o -path '*/@eaDir/*' \) -prune -o \
  -type f -exec stat -c '%s	%n' {} + |
awk -F '	' -v min="$MIN_SIZE" '$1 >= min { print }' |
sort -n -k1,1 > "$TMP"

awk -F '	' -v tol="$TOL" -v out="$OUT" '
BEGIN {
  print "group_id\tsize_bytes\tpath" > out
  gid = 0
  count = 0
  candidate_files = 0
}

function reset_group(size, path) {
  count = 1
  start_size = size
  sizes[1] = size
  paths[1] = path
}

function flush_group(    i) {
  if (count > 1) {
    gid++
    for (i = 1; i <= count; i++) {
      print gid "\t" sizes[i] "\t" paths[i] >> out
      candidate_files++
    }
  }
  delete sizes
  delete paths
  count = 0
}

{
  size = $1 + 0
  path = $0
  sub(/^[^\t]*\t/, "", path)

  if (count == 0) {
    reset_group(size, path)
    next
  }

  if ((size - start_size) <= tol) {
    count++
    sizes[count] = size
    paths[count] = path
  } else {
    flush_group()
    reset_group(size, path)
  }
}

END {
  flush_group()
  print "Candidate groups: " gid
  print "Candidate files: " candidate_files
}
' "$TMP"

wc -l "$OUT" | awk '{ print "Output rows including header: " $1 }'

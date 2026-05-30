#!/bin/sh
set -eu 

ROOT="."

usage() {
  echo "Usage:"
  echo "  ./Find-Dupe-Candidates.sh [-r ROOT] [-o OUTPUT.tsv] [-b TOLERANCE_BYTES] [-m MIN_SIZE_BYTES]"
  echo
  echo "Defaults:"
  echo "  ROOT=."
  echo "  OUTPUT=dupe-candidates.tsv"
  echo "  TOLERANCE_BYTES=0"
  echo "  MIN_SIZE_BYTES=1"
  echo
  echo "Examples:"
  echo "  ./Find-Dupe-Candidates.sh"
  echo "  ./Find-Dupe-Candidates.sh -r /volume1/SchoolBoardArchive"
  echo "  ./Find-Dupe-Candidates.sh -b 1024 -m 1048576"
  exit 1
}

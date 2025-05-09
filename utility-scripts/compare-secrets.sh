#!/bin/bash

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <original_dir> <regenerated_dir>"
  exit 1
fi

ORIGINAL="$1"
REGENERATED="$2"

echo "Comparing directories recursively (ignoring metadata):"
echo "   Original:    $ORIGINAL"
echo "   Regenerated: $REGENERATED"
echo

diff -ru "$ORIGINAL" "$REGENERATED" | \
sed -E 's|^(--- .+)[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}.*$|\1|; s|^(\+\+\+ .+)[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}.*$|\1|'

#!/usr/bin/env bash
set -euo pipefail

name="${1:-world}"
for index in 1 2 3; do
  printf 'hello %s (%d)\n' "$name" "$index"
done

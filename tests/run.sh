#!/bin/sh
# Runs the mocked logic tests with whatever Lua is on PATH. From the repo root: tests/run.sh
for l in lua lua5.4 lua5.3 luajit; do
  if command -v $l >/dev/null 2>&1; then exec $l tests/test_spoon.lua; fi
done
echo "no lua interpreter found (brew install lua)"; exit 2

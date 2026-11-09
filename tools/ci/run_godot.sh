#!/usr/bin/env bash
# Runs a Godot command with a time limit. If it crashes (dies from a signal),
# runs it once more under gdb and prints the backtrace, so a crash in the sim
# core's native code (sim/native) is readable in the CI log.
#
#   tools/ci/run_godot.sh <seconds> godot <args...>
set -uo pipefail

limit="$1"
shift
timeout "$limit" "$@"
status=$?
# 124 is timeout's own "took too long"; 128 + n means killed by signal n.
if [ "$status" -gt 128 ]; then
  echo "::error::$1 crashed (exit $status). Running it again under gdb for a backtrace."
  if ! command -v gdb > /dev/null; then
    sudo apt-get install -y -q gdb > /dev/null 2>&1 || true
  fi
  if command -v gdb > /dev/null; then
    timeout "$limit" gdb -batch -nx -ex "set pagination off" -ex run -ex "bt 50" -ex "info sharedlibrary" --args "$@" 2>&1 | tail -150
  fi
fi
exit "$status"

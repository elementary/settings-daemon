#!/bin/sh
# Run in the isolated SDK copy, not against the desktop session.
set -eu
test "${EQ_PRIVATE_TEST:-}" = 1
test ! -e /dev/snd
cd "$(dirname "$0")/.."
# Native lifecycle and controls use the companion Sound tests/run-active-bridge.sh.
python3 tests/profile-files.py
cc tests/render-graph.c $(pkg-config --cflags --libs libpipewire-0.3) -o tests/render-graph
python3 tests/generic-envelope.py

#!/bin/sh
# Run in the isolated SDK copy, not against the desktop session.
set -eu
test "${EQ_PRIVATE_TEST:-}" = 1
test ! -e /dev/snd
cd "$(dirname "$0")/.."
# Native lifecycle/controls exercise the actual backend in the companion
# Sound tests/run-active-bridge.sh; the removed C-wrapper tests are archived in R2.
python3 tests/profile-files.py

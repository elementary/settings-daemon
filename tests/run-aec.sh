#!/bin/sh
# Existing private SDK only; never connect to the desktop audio server.
set -eu
test "${AEC_PRIVATE_TEST:-}" = 1
test ! -e /dev/snd
cd "$(dirname "$0")/.."
build_dir="$PWD/tests/aec/build"
mkdir -p "$build_dir/schemas"
cp data/io.elementary.settings-daemon.gschema.xml "$build_dir/schemas/"
glib-compile-schemas "$build_dir/schemas"
cc -shared -fPIC -Wall -Wextra -Werror tests/aec/endpoint-delay.c \
    $(pkg-config --cflags --libs libpulse) -ldl -o "$build_dir/endpoint-delay.so"
valac --pkg libpulse --pkg libpulse-mainloop-glib --pkg gio-2.0 --pkg libpulse-operation \
    --vapidir=vapi -X '-DGETTEXT_PACKAGE="io.elementary.settings-daemon"' \
    -o "$build_dir/owner" src/Backends/EchoProcessor.vala tests/aec/owner.vala
python3 tests/aec/reconnect.py

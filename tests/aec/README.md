Run in an isolated copy of this checkout in the existing private SDK, with no
`/dev/snd` and with libpulse development files, valac, PipeWire, pipewire-pulse,
WirePlumber, pactl and the ALSA null plugin available:

```
AEC_PRIVATE_TEST=1 sh tests/run-aec.sh
```

The runner compiles the production EchoProcessor directly, independently of EQ.
It uses private runtime/config directories and ALSA null devices, following the
companion Sound harness. Only the owner receives an LD_PRELOAD fault shim:
following a successful native module load, native endpoint queries temporarily
return NOENTITY. Real endpoint notifications wake the production activation path.

The three cases cover publication within the deadline, expiration while restoring
a saved preference, and expiration after an explicit enable. The timeout cases
check cleanup, preference retention versus explicit rollback, no repeated loads
under further device notifications, and recovery after a deliberate disable/enable.
On the original source, delayed publication causes immediate activation failure
and saved-preference rollback. The short-delay case should fail there.

This models the asynchronous publication race; it does not reproduce HDA discovery
or establish that endpoint publication was the actual trigger in F2. Run the
companion lifecycle/ownership/stream suite and the parent hardware restart check
separately. Generated files stay under `tests/aec/build`.

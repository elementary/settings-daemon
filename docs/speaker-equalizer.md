# Speaker equalizer

Settings-daemon owns processing and reconnects independently of Sound Settings.
EQ attaches to the physical output, preserving its volume, mute, balance and
routing. It does not create a second EQ output.

The five controls are Bass (low shelf), Low mids, Mids, Air (peaks), and Upper
balance (high shelf). Their names are fixed in Sound. Profiles specify each
filter's frequency, Q, gain range and optional recommended gain. The generic
profile has neutral gains and starts disabled.

Root-installed profiles live in `${datadir}/io.elementary.settings-daemon/equalizers/v1`.
Profiles and parent directories must be root-owned, not writable by other users,
and not symlinks. A declared invalid or missing profile does not fall back.

Vendor policy handles hardware matching, installs a matching neutral graph on
the physical output, and sets `elementary.eq.profile` to the profile ID. It may
use a schema override to enable recommended profiles initially. Stored user
preferences always win. Other routes keep the same graph layout with independent
neutral defaults. Reset restores recommendations without changing On/Off.

The graph uses five series biquads `eos_eq_1` through `eos_eq_5`, followed by
`eos_eq_h` with Mult=1, Add=0 and Control=0. It starts at zero gain. Set
`node.cache-params=false`; the daemon validates fresh controls before writing.
WirePlumber >= 0.5.13 and PipeWire >= 1.4 are required for graph provisioning.

Off restores zero gains and unity; the graph remains attached. There is no
automatic attenuation or limiter. Another client's control changes are left
alone until the user changes a preference and validation succeeds.

Private integration checks run in the existing SDK without `/dev/snd`:

```
EQ_PRIVATE_TEST=1 sh tests/run-components.sh
```

The companion Sound runner takes this daemon source plus the matching vendor
rule/profile via `EQ_OEM_RULE` and `EQ_OEM_PROFILE`.

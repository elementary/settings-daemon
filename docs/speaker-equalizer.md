# Speaker equalizer contract

The existing session Audio owner supplies EQ alongside WebRTC noise and echo
cancellation. Sound reads its status and writes relocatable GSettings; it does
not create graphs or connect to PipeWire. The native EQ client uses libWirePlumber.
Shipping graph policy requires WirePlumber >= 0.5.13 and PipeWire >= 1.4.

## Trusted layout and output ownership

Root profiles live under `${datadir}/io.elementary.settings-daemon/equalizers/v1`.
Files and every parent must be root-owned, non-writable by other users and not
symlinks. The existing bounded reader accepts only regular files and profile IDs.
A declared missing, malformed or untrusted OEM profile fails closed; it never
falls back to generic data.

Every profile and graph has the same five fixed bands:

| Frequency | Type | Q |
| --- | --- | --- |
| 105 Hz | Low shelf | 0.80 |
| 190 Hz | Low shelf | 0.75 |
| 280 Hz | Peak | 1.00 |
| 2800 Hz | Peak | 1.10 |
| 8500 Hz | High shelf | 0.70 |

The physical sink must match the profile's exact Node, current serial and device
ID between PulseAudio and PipeWire, and expose the selected route among
its ports when it has ports. Only `generic-speakers-v1` may use `Node=*` and
`Route=*`, bound to that verified physical sink and its current route. A valid
OEM profile supplies recommendations only on its declared route; other routes
use the generic layout and separate preferences. Invalid OEM profiles still
fail closed. An owned
AEC alias resolves to its physical master; virtual/filter endpoints are excluded.
Vendor hardware matching remains distribution policy, outside the generic daemon.
Bluetooth headset loopbacks do not currently receive this graph policy.

The installed 50 rule supplies a neutral graph for unprofiled ALSA outputs.
Subsequent OEM 51 rules replace its marker, selecting only their own graph. No
additional visible output is created. A changed physical default first retires
the old owned graph to zero gains/unity, including an idle initialized graph,
then disconnects and follows the selected output. Previously selected outputs
remain neutral; the daemon does not become a persistent multi-output owner.

Graph zero contains five series biquads `eos_eq_1` through `eos_eq_5`, then the
linear `eos_eq_h`. Gains start at zero, Mult at one, Add/Control at zero.
`node.cache-params=false` exposes fresh metadata. Both PropInfo and Props must
contain all 48 reserved controls exactly once, with matching frequency/Q and
fixed linear controls. This detects observable collisions; it is not a privileged
ownership boundary against another session client or proof of hidden topology.

## Gains and defaults

There are five gain sliders, On/Off and Reset. Preferences are scoped by profile
ID, physical node name and selected route. Empty DefaultGains means no device
recommendations; five defaults supply them. Generic gains range from −12 to +12 dB.
OEM ranges must include their recommendations; the existing StarFighter +7.5/+8 dB
curve remains valid.

Absent user gain values resolve to recommendations or zeros. A distribution's
existing enabled schema override applies initially only to a recommended device
profile; generic layouts start Off. Stored user gains and On/Off values always
win. Policy updates never write them. Reset stores recommendations or zeros and
preserves On/Off. Off bypasses with zero/unity while keeping saved slider values.
There is no preset key, selector, editable frequency/Q or graph API.

The graph multiplier remains at unity for every curve. Boosting bands does not
reduce the other frequencies or change physical volume, balance or mute. There
is no automatic gain compensation or limiter; boosted signals can clip. Older
profiles may contain Headroom, which is ignored.

## Failures and lifecycle

Availability means a validated profile and selected route, independently of the
last native operation. Supported failures retain their error. A deliberate changed
ON request from OFF, or changed gains, authorizes bounded fresh validation; Off
still withdraws a saved enabled preference. Invalid profiles/routes remain
unavailable, and malformed graphs still reject native writes.

Unchanged notifications, rediscovery, idle/resume and reconnect only audit; they
never reset failed state or overwrite foreign controls. Each changed request has
at most one six-control write, followed by fresh readback. Existing generation,
revision/core guards, cancellation and two-second native deadlines remain. An
idle selected node waits for running confirmation; retirement can validate and
neutralize its already initialized graph while idle.

## Validation

In the existing private SDK, with no `/dev/snd`:

```
EQ_PRIVATE_TEST=1 sh tests/run-components.sh                 # daemon checkout
EQ_PRIVATE_TEST=1 EQ_OEM_RULE=<reviewed-51-rule> \
    EQ_OEM_PROFILE=<matching-root-profile> \
    sh tests/run-components.sh <daemon-source>              # Sound checkout
```

The existing runners execute root-reader checks, production model/GTK tests,
actual private PW/Pulse/WP bridge and native SPA PCM rendering. Native ALSA rule
matching uses WpConf/WpJson APIs with synthetic card properties; these fixtures
do not establish real hardware discovery or acoustic results. Meson/DEB build
checks and upstream build/lint CI are separate from these executed runtime tests.

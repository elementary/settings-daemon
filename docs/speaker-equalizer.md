# Speaker equalizer contract, version 1

Review candidate on `speaker-eq`, based on `59c80f5`. The companion Sound
change is based on `08b0dd6`. Neither change is ready for packaging until two
independent security and human/minimality reviews cover the frozen sources.

The existing session settings daemon owns one native PipeWire connection.
Sound writes relocatable GSettings preferences and reads the existing Audio
D-Bus object's separate `GetEqualizerStatus`/`EqualizerChanged` interface.
The existing echo-cancellation status tuple and EchoProcessor are unchanged.
There is no Sound-side PipeWire client, graph setter, plugin selector, new
service or DSP implementation. The client uses libWirePlumber >= 0.5.0 directly from Vala. Meson generates
its VAPI from the installed Wp-0.5 GIR; only three metadata corrections are
maintained. The remaining C file securely opens root-installed profiles.
Pure PulseAudio reports EQ unavailable and keeps its AEC path.

Build/API minimum and tested runtime are separate. The WpCore sync/connect,
ObjectManager, Node, async enum/set_param and SpaPod builder/iterator APIs used
here exist in the upstream 0.5.0 headers. The physical audioconvert filter-graph
feature and node.cache-params option exist in PipeWire 1.4.0. Neither fact is a
runtime compatibility test. This candidate was exercised on PW 1.6.2, libWP
0.5.13, Vala 0.56.19, GTK 4.22.4 and Granite 7.8.1. The project's existing
GTK >= 4.20 requirement is unchanged. Production no longer directly requires
PipeWire/SPA development headers; the private SPA Device fixture does.
Older runtimes need the same native controls/metadata/lifecycle verification
before distribution support is claimed. A WP policy daemon is not required
by the library client; a distribution still owns graph/route provisioning.

## Root-installed policy and profile

Profiles live in `${datadir}/io.elementary.settings-daemon/equalizers/v1/`.
The directory and all parents must be root-owned and not group/world writable.
The same rules apply to each regular profile file (maximum 8192 bytes).
Symlinks and profile IDs other than 1–64 ASCII letters, digits, `_` and `-`
are refused. There is no home-directory override or caller-supplied path.
Version 1 profile content is illustrated by `tests/fixture-v1.ini`; it is a
synthetic test fixture and is deliberately not installed as hardware tuning.

The physical node must carry `elementary.eq.profile = <profile-id>` and match
the profile's exact `Node` and active PulseAudio speaker `Route`. Its current
`object.serial` and `device.id` must agree between PulseAudio and native
PipeWire. AEC's exactly owned output alias resolves to its physical master.
Virtual/filter endpoints and endpoints with a master device are excluded.
There are no DMI checks or vendor/device presets in this implementation.

The profile provider owns root WirePlumber graph/lifecycle policy. A provider
must demonstrate ordinary speaker/headphone switching and node recreation
with the daemon as the sole six-control writer before adopting a profile:

* Install the five built-in biquads in audioconvert graph zero, in profile
  order, named `eos_eq_1` through `eos_eq_5`. Labels corresponding to `Types`
  are `bq_lowshelf`, `bq_peaking`, and `bq_highshelf`. Frequencies and Q are
  immutable. Initial gains must be zero; the daemon applies user preferences.
* A final built-in `linear` node named `eos_eq_h` supplies profile `Headroom`
  through `Mult` when enabled, and unity for Off/Flat. Initialize `Mult` to 1.
  The daemon owns this sixth fixed setter; `Add` and `Control` must remain zero. Connect its
  audio input/output in series; no control links, channel gain/volume mappings,
  other uses of `eos_eq_`, or concurrent owners of these names are allowed.
* Start the physical graph neutral and validate ordinary route changes with
  the daemon's six-control bypass. It manages the selected physical node,
  not every inactive node. Include previously selected/nondefault nodes in
  downstream route testing; this candidate does not prove that delivery path.
* Set `node.cache-params=false` on the profiled node before graph installation.
  With default caching in the tested PW 1.6.2 bridge, PropInfo stayed stale
  after graph installation while Props exposed all 48 controls; the backend
  correctly refused that incomplete metadata. This requirement is confined
  to the profiled node, not a global cache change. PW 1.6.2 defaults caching to
  true in [impl-node.c](https://github.com/PipeWire/pipewire/blob/1.6.2/src/pipewire/impl-node.c#L1091).
* Remove any old downstream EQ graph before adoption, so the two cannot stack.

`FirstGraph=true` and `Namespace=eos_eq` declare this installation contract.
They are **not cryptographic ownership, a privilege boundary against another
session client, or proof of graph topology**. PipeWire PropInfo exposes the
first graph's controls; Props can enumerate multiple graphs. The backend
requires all 48 reserved controls exactly once in both metadata and values,
validates frequency/Q and the fixed linear controls, and rejects unknown/duplicate reserved names.
This catches observable collisions, not malicious topology impersonation.
Graph labels, links, coefficients' provenance and physical identity ultimately
depend on the root policy. If stronger ownership is required, this API cannot
provide it; do not invent a graph-text or privileged broker workaround.

## Preferences and headroom

Each profile revision + physical node name + speaker route hashes to a stable
relocatable GSettings path. Runtime IDs do not become preference identifiers.
Enabled Device Default sends the five factory gains; Custom sends five bounded
stored gains. Flat and disabled send five zero gains. Reset restores factory
gains and selects Device Default, preserving the enabled setting. Arbitrary
frequencies, Q, plugins, files or graph text are never accepted from Sound.

**Only five Gain controls and `eos_eq_h:Mult` are written.** Enabled Device
Default/Custom uses the immutable profile's headroom value. Off and Flat use
zero gains and unity headroom, restoring pre-graph loudness within the declared
series-graph contract. Physical volume, balance and mute are untouched. This
sixth setter follows the explicit product decision; there is no headroom UI,
user-supplied multiplier, extra D-Bus method or graph API.

The root profile author must approve headroom for the complete allowed gain
envelope and device. Finite/range checks do not establish clipping protection.
There is no limiter or invented factory compensation. No real device profile
or production WirePlumber policy is supplied in this upstream candidate.

## Native lifecycle and limitations

GSettings events coalesce over 100 ms. PA discovery has a two-second deadline
and generation checks. PA notifications mark discovery pending and hide applied
status while querying. Unchanged identity/profile content/preferences do not
invalidate or reissue the native request; a failed foreign-control audit stays
failed. Changed serial/device/name/profile/port or saved preferences authorizes
a new bounded request. Invalid discovery revokes the request. The native
backend matches the current serial, freshly enumerates metadata and values,
sends only six fixed parameters, awaits WpCore.sync, then freshly enumerates
again before confirming. This uses asynchronous enum_params, not libWP's
cached enum_params_sync. Each native round has a two-second deadline. A
stalled round cancels and disconnects its Core: native tests showed that
GCancellable alone does not complete stalled libWP enumeration/sync until
the server responds. Revision/core guards reject stale completions.

Idle nodes remain unconfirmed until Node state_changed reports RUNNING.
A changed request authorizes at most one write attempt. That permission is
consumed before the write; notifications, unchanged PA discovery, idle/resume
and reconnect are read-only audits. Foreign gains/headroom fail without being
overwritten. A pending, never-attempted explicit request can finish after
reconnect only after identity and all controls validate again.
A valid saved enabled preference can be withdrawn
through Off while native status is failed; enable/preset/gain controls remain
blocked until available. Invalid graph controls still prevent native writes. Native connection loss triggers daemon rediscovery
after two seconds. PipeWire's full Props (including volume/mute/balance),
`filter-graph.disable`, defaults and stream routing are never written by EQ.

The final evidence report distinguishes tests from untested lifecycle paths.
The synthetic active bridge now exercises real PA profile/route discovery,
production daemon/model, GSettings and native controls together. It does not
prove real device policy, suspend/resume,
channel acoustics, production clipping safety, or AEC convergence. The AEC
reference remains upstream of physical-node EQ; a required post-EQ reference
would be a separate topology decision. Downstream factory migration remains
separate. Fedora implementation remains out of scope and gated by the fresh
current signed Ubuntu ISO prerequisite.

Primary API/source references:
[PW node API](https://docs.pipewire.org/group__pw__node.html),
[filter-chain controls](https://docs.pipewire.org/page_module_filter_chain.html),
[PW 1.6.2 native sequences](https://github.com/PipeWire/pipewire/blob/1.6.2/src/modules/module-protocol-native/protocol-native.c),
[PW 1.6.2 built-ins](https://github.com/PipeWire/pipewire/blob/1.6.2/spa/plugins/filter-graph/plugin_builtin.c),
[WirePlumber software DSP](https://pipewire.pages.freedesktop.org/wireplumber/policies/software_dsp.html).

## Downstream speaker-route delivery gate

The practical provider contract is a neutral physical graph at creation
(zero gains, linear Mult=1), the real root profile/marker/cache setting, and
ordinary route/lifecycle validation. The daemon alone writes the six controls:
observed non-speaker or unknown active ports on the same validated physical
node request zero/unity; speaker return restores saved preferences. It does
not reset physical volume. Real hotplug, manual port/default changes, stream
continuity and any audible transition remain downstream integration checks.
Observed post-route bypass is not a claim of sample-atomic switching. There
is no all-writers barrier against arbitrary direct SPA/root writers, no new
broker, and no second setter racing the daemon's foreign-control audit.

Vale's existing `vale-speaker-route.lua` and stock smart-filter disabled
metadata control its old paired virtual filter. They do not automatically
provide lifecycle semantics for the new physical-node graph. Reuse the
existing policy location, and remove the old graph before adopting the new
one. The current source candidate supplies no shipping hardware profile.

The actual existing StarFighter values are 105 Hz/Q .80/+7.5 dB,
190/.75/+8, 280/1/-1.5, 2800/1.1/+1.5, 8500/.7/+.5 (two low shelves,
two peaks, one high shelf). Factory profile/envelope and fixed headroom remain
separate work. Derive headroom from the actual native biquad response across
the allowed gain envelope, with native DSP clipping controls. The synthetic
fixture's .25 is not calibration; a sampled sinusoidal bound alone is not a
proof for arbitrary PCM transients. Hardware acoustics may remain untested
without blocking a demonstrated digital envelope. No vendor/DMI preset enters
this generic upstream implementation.

Version rationale: [WP 0.5.0 Core](https://github.com/PipeWire/wireplumber/blob/0.5.0/lib/wp/core.h),
[WP 0.5.0 parameter API](https://github.com/PipeWire/wireplumber/blob/0.5.0/lib/wp/proxy-interfaces.h),
[WP 0.5.0 pods](https://github.com/PipeWire/wireplumber/blob/0.5.0/lib/wp/spa-pod.h),
[PW 1.4.0 NEWS](https://github.com/PipeWire/pipewire/blob/1.4.0/NEWS),
[PW 1.4.0 cache policy](https://github.com/PipeWire/pipewire/blob/1.4.0/src/pipewire/impl-node.c).

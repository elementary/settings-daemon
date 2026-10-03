/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 elementary, Inc. (https://elementary.io)
 */

[DBus (name = "io.elementary.settings_daemon.Audio")]
public class SettingsDaemon.Backends.Audio : Object {
    public struct Status {
        public bool enabled;
        public bool available;
        public bool busy;
        public string error;
        public string source_master;
        public string sink_master;
    }

    public struct EqualizerStatus {
        public bool available;
        public bool busy;
        public bool applied;
        public string error;
        public string settings_path;
        public string node;
        public string route;
        public double[] frequencies;
        public string[] types;
        public double[] defaults;
        public double[] minimum;
        public double[] maximum;
    }

    public signal void state_changed ();
    public signal void equalizer_changed ();
    private PulseAudio.GLibMainLoop loop = new PulseAudio.GLibMainLoop ();
    private PulseAudio.Context context;
    private EchoProcessor? processor;
    private SpeakerEqualizer? equalizer;
    private uint reconnect_id;

    [DBus (visible = false)]
    public void start () {
        connect_audio ();
    }

    public Status get_status () throws DBusError, IOError {
        if (processor == null) {
            return { false, false, false, _("Could not connect to the audio server."), "", "" };
        }
        return { processor.enabled, processor.available, processor.busy,
            processor.error ?? "", processor.source_alias ?? "", processor.sink_alias ?? "" };
    }

    public EqualizerStatus get_equalizer_status () throws DBusError, IOError {
        if (equalizer != null) return equalizer.get_status ();
        return { false, false, false, _("The audio service is unavailable."), "", "", "",
            new double[0], new string[0], new double[0], new double[0], new double[0] };
    }

    private void connect_audio () {
        context = new PulseAudio.Context (loop.get_api (), "elementary Settings Daemon");
        context.set_state_callback ((c) => {
            switch (c.get_state ()) {
                case PulseAudio.Context.State.READY:
                    processor = new EchoProcessor (c);
                    equalizer = new SpeakerEqualizer (c);
                    equalizer.changed.connect (() => equalizer_changed ());
                    processor.notify.connect (() => state_changed ());
                    string? last_echo_master = null;
                    processor.notify.connect (() => {
                        if (processor != null && equalizer != null && last_echo_master != processor.sink_alias) {
                            last_echo_master = processor.sink_alias;
                            equalizer.refresh (last_echo_master);
                        }
                    });
                    c.set_subscribe_callback ((connection, event, index) => {
                        var facility = event & PulseAudio.Context.SubscriptionEventType.FACILITY_MASK;
                        if (facility == PulseAudio.Context.SubscriptionEventType.SERVER ||
                            facility == PulseAudio.Context.SubscriptionEventType.SINK ||
                            facility == PulseAudio.Context.SubscriptionEventType.CARD) {
                            equalizer.refresh (processor.sink_alias);
                        }
                        if (facility == PulseAudio.Context.SubscriptionEventType.SERVER) {
                            processor.observe_defaults ();
                        } else if (facility == PulseAudio.Context.SubscriptionEventType.MODULE &&
                            (event & PulseAudio.Context.SubscriptionEventType.TYPE_MASK) ==
                                PulseAudio.Context.SubscriptionEventType.REMOVE) {
                            processor.module_removed (index);
                        } else {
                            processor.refresh ();
                        }
                    });
                    c.subscribe (PulseAudio.Context.SubscriptionMask.SERVER |
                        PulseAudio.Context.SubscriptionMask.SOURCE | PulseAudio.Context.SubscriptionMask.SINK |
                        PulseAudio.Context.SubscriptionMask.MODULE | PulseAudio.Context.SubscriptionMask.SOURCE_OUTPUT |
                        PulseAudio.Context.SubscriptionMask.SINK_INPUT | PulseAudio.Context.SubscriptionMask.CARD);
                    processor.observe_defaults ();
                    equalizer.refresh (processor.sink_alias);
                    state_changed ();
                    break;
                case PulseAudio.Context.State.FAILED:
                case PulseAudio.Context.State.TERMINATED:
                    if (equalizer != null) equalizer.stop ();
                    equalizer = null;
                    equalizer_changed ();
                    if (processor != null) {
                        processor.stop ();
                    }
                    processor = null;
                    c.set_subscribe_callback (null);
                    c.set_state_callback (null);
                    c.disconnect ();
                    state_changed ();
                    if (reconnect_id == 0) {
                        reconnect_id = Timeout.add_seconds (2, () => {
                            reconnect_id = 0;
                            connect_audio ();
                            return Source.REMOVE;
                        });
                    }
                    break;
                default:
                    break;
            }
        });
        context.connect (null, PulseAudio.Context.Flags.NOAUTOSPAWN);
    }
}

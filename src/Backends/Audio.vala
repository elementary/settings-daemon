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

    public signal void state_changed ();
    private PulseAudio.GLibMainLoop loop = new PulseAudio.GLibMainLoop ();
    private PulseAudio.Context context;
    private EchoProcessor? processor;
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

    private void connect_audio () {
        context = new PulseAudio.Context (loop.get_api (), "elementary Settings Daemon");
        context.set_state_callback ((c) => {
            switch (c.get_state ()) {
                case PulseAudio.Context.State.READY:
                    processor = new EchoProcessor (c);
                    processor.notify.connect (() => state_changed ());
                    c.set_subscribe_callback ((connection, event, index) => {
                        var facility = event & PulseAudio.Context.SubscriptionEventType.FACILITY_MASK;
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
                        PulseAudio.Context.SubscriptionMask.SINK_INPUT | PulseAudio.Context.SubscriptionMask.CARD,
                        (connection, success) => {
                            if (success == 1 && processor != null && processor.context == connection) {
                                processor.observe_defaults ();
                            }
                        });
                    state_changed ();
                    break;
                case PulseAudio.Context.State.FAILED:
                case PulseAudio.Context.State.TERMINATED:
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

/*
 * SPDX-License-Identifier: LGPL-2.0-or-later
 * SPDX-FileCopyrightText: 2026 elementary, Inc. (https://elementary.io)
 */

internal class SettingsDaemon.Backends.EchoProcessor : Object {
    public const string SOURCE_NAME = "elementary_echo_cancel_source";
    public const string SINK_NAME = "elementary_echo_cancel_sink";

    public PulseAudio.Context context { get; construct; }
    public bool enabled { get; private set; }
    public bool available { get; private set; }
    public bool busy { get; private set; }
    public string? error { get; private set; }
    public string? source_master { get; private set; }
    public string? sink_master { get; private set; }

    public string? source_alias {
        get {
            return module_index != PulseAudio.INVALID_INDEX && source_index != PulseAudio.INVALID_INDEX ?
                source_master : null;
        }
    }
    public string? sink_alias {
        get {
            return module_index != PulseAudio.INVALID_INDEX && sink_index != PulseAudio.INVALID_INDEX ?
                sink_master : null;
        }
    }

    private Settings settings = new Settings ("io.elementary.settings-daemon.audio");
    private uint32 module_index = PulseAudio.INVALID_INDEX;
    private uint32 source_index = PulseAudio.INVALID_INDEX;
    private uint32 sink_index = PulseAudio.INVALID_INDEX;
    private struct RestoredStream {
        public uint32 index;
        public string target;
    }
    private RestoredStream[] restored_recordings = {};
    private RestoredStream[] restored_playbacks = {};
    private bool pending;
    private bool reconciling;
    private bool restoring_preference;
    private bool restore_failed;
    private uint refresh_id;
    private string? observed_source;
    private string? observed_sink;
    private signal void defaults_changed ();
    private signal void endpoints_changed ();

    public void observe_defaults () {
        context.get_server_info ((c, info) => {
            if (info != null) {
                observed_source = info.default_source_name;
                observed_sink = info.default_sink_name;
                defaults_changed ();
                refresh ();
            }
        });
    }

    public EchoProcessor (PulseAudio.Context context) {
        Object (context: context);
    }

    construct {
        restoring_preference = settings.get_boolean ("echo-cancellation");
        settings.changed["echo-cancellation"].connect (preference_changed);
    }

    public void stop () {
        restored_recordings = {};
        restored_playbacks = {};
        settings.changed["echo-cancellation"].disconnect (preference_changed);
        if (refresh_id != 0) {
            Source.remove (refresh_id);
            refresh_id = 0;
        }
    }

    private void preference_changed () {
        if (!settings.get_boolean ("echo-cancellation")) {
            restored_recordings = {};
            restored_playbacks = {};
        }
        restoring_preference = false;
        restore_failed = false;
        refresh ();
    }

    private void enable_failed () {
        if (!restoring_preference) {
            settings.set_boolean ("echo-cancellation", false);
        }
        // Keep the failed request and diagnostic until the next user change.
        restore_failed = true;
    }

    public void refresh () {
        endpoints_changed ();
        pending = true;
        busy = true;
        if (reconciling || refresh_id != 0) {
            return;
        }

        // Coalesce a burst of device/default events before replacing the
        // filter. PipeWire applies paired metadata selections asynchronously.
        refresh_id = Timeout.add (100, () => {
            refresh_id = 0;
            reconcile.begin ();
            return Source.REMOVE;
        });
    }

    public void module_removed (uint32 index) {
        if (index == module_index) {
            module_index = PulseAudio.INVALID_INDEX;
            source_master = sink_master = null;
            enabled = false;
        }

        refresh ();
    }

    // These arguments are PulseAudio module arguments, never shell commands.
    private static string quote (string name) {
        return "\"%s\"".printf (name.replace ("\\", "\\\\").replace ("\"", "\\\""));
    }

    private static string arguments (string source, string sink) {
        string owner = "device.echo_cancel.owner=io.elementary.settings.sound";
        return "source_master=%s sink_master=%s source_name=%s sink_name=%s ".printf (
            quote (source), quote (sink), SOURCE_NAME, SINK_NAME
        ) + "aec_method=webrtc aec_args=\"analog_gain_control=0 digital_gain_control=0\" " +
            "source_properties=%s sink_properties=%s".printf (
                quote (owner + " device.master_device=" + source),
                quote (owner + " device.master_device=" + sink)
            );
    }

    private async bool discover_module () {
        bool complete = false;
        uint32 discovered_index = PulseAudio.INVALID_INDEX;
        string? discovered_source = null;
        string? discovered_sink = null;
        var operation = context.get_module_info_list ((c, info, eol) => {
            if (eol != 0) {
                complete = eol > 0;
            }
            if (info == null || info.name != "module-echo-cancel" || info.argument == null) {
                return;
            }

            // Adopt only a module with the exact arguments we generate. Never
            // unload another application's filter, even if its names collide.
            try {
                string[] words;
                Shell.parse_argv (info.argument, out words);
                string? source = null;
                string? sink = null;
                foreach (var word in words) {
                    if (word.has_prefix ("source_master=")) {
                        source = word.substring (14);
                    } else if (word.has_prefix ("sink_master=")) {
                        sink = word.substring (12);
                    }
                }

                if (source != null && sink != null && info.argument == arguments (source, sink)) {
                    discovered_index = info.index;
                    discovered_source = source;
                    discovered_sink = sink;
                }
            } catch (ShellError e) {
                warning ("Reading echo cancellation module arguments failed: %s", e.message);
            }
        });
        var success = (yield wait (operation)) && complete;
        if (success && discovered_index != PulseAudio.INVALID_INDEX) {
            module_index = discovered_index;
            source_master = discovered_source;
            sink_master = discovered_sink;
        }
        return success;
    }

    // Completion, cancellation, disconnect and timeout all resume the caller.
    // Cancel before releasing callback data on timeout (libpulse's contract).
    private async bool wait (PulseAudio.Operation? operation) {
        if (operation == null) {
            return false;
        }

        if (operation.get_state () != PulseAudio.Operation.State.RUNNING) {
            return operation.get_state () == PulseAudio.Operation.State.DONE;
        }

        bool timed_out = false;
        var timeout = new TimeoutSource (5000);
        timeout.set_callback (() => {
            timed_out = true;
            operation.cancel ();
            wait.callback ();
            return Source.REMOVE;
        });
        PulseAudio.operation_set_state_callback (operation, (op) => {
            if (!timed_out && op.get_state () != PulseAudio.Operation.State.RUNNING) {
                timeout.destroy ();
                wait.callback ();
            }
        });
        timeout.attach ();
        yield;
        PulseAudio.operation_set_state_callback (operation, null);
        return !timed_out && operation.get_state () == PulseAudio.Operation.State.DONE;
    }

    private async bool server_defaults (out string? source, out string? sink) {
        string? current_source = null;
        string? current_sink = null;
        var operation = context.get_server_info ((c, info) => {
            if (info != null) {
                current_source = info.default_source_name;
                current_sink = info.default_sink_name;
                observed_source = current_source;
                observed_sink = current_sink;
            }
        });
        var success = yield wait (operation);
        source = current_source;
        sink = current_sink;
        return success && source != null && sink != null;
    }

    private struct Endpoint {
        public bool complete;
        public bool exists;
        public bool physical;
        public bool is_owned;
        public uint32 index;
    }

    private async Endpoint source_info (string? name) {
        Endpoint result = { false, false, false, false, PulseAudio.INVALID_INDEX };
        if (name == null) {
            return result;
        }
        var op = context.get_source_info_by_name (name, (c, info, eol) => {
            if (eol != 0) {
                result.complete = eol > 0 || c.errno () == PulseAudio.Error.NOENTITY;
            } else if (info != null) {
                result.exists = true;
                result.index = info.index;
                result.is_owned = info.owner_module == module_index &&
                    info.proplist.gets ("device.echo_cancel.owner") == "io.elementary.settings.sound";
                result.physical = name != SOURCE_NAME && !name.has_suffix (".monitor") &&
                    info.monitor_of_sink == PulseAudio.INVALID_INDEX &&
                    info.proplist.gets ("device.class") != "filter" &&
                    info.proplist.gets ("node.virtual") != "true" &&
                    info.proplist.gets ("device.master_device") == null &&
                    (PulseAudio.SourceFlags.HARDWARE in info.flags || info.card != PulseAudio.INVALID_INDEX);

            }
        });
        if (!(yield wait (op)) || !result.complete) {
            result = { false, false, false, false, PulseAudio.INVALID_INDEX };
        }
        return result;
    }

    private async Endpoint sink_info (string? name) {
        Endpoint result = { false, false, false, false, PulseAudio.INVALID_INDEX };
        if (name == null) {
            return result;
        }
        var op = context.get_sink_info_by_name (name, (c, info, eol) => {
            if (eol != 0) {
                result.complete = eol > 0 || c.errno () == PulseAudio.Error.NOENTITY;
            } else if (info != null) {
                result.exists = true;
                result.index = info.index;
                result.is_owned = info.owner_module == module_index &&
                    info.proplist.gets ("device.echo_cancel.owner") == "io.elementary.settings.sound";
                result.physical = name != SINK_NAME &&
                    info.proplist.gets ("device.class") != "filter" &&
                    info.proplist.gets ("node.virtual") != "true" &&
                    info.proplist.gets ("device.master_device") == null &&
                    (PulseAudio.SinkFlags.HARDWARE in info.flags || info.card != PulseAudio.INVALID_INDEX);
            }
        });
        if (!(yield wait (op)) || !result.complete) {
            result = { false, false, false, false, PulseAudio.INVALID_INDEX };
        }
        return result;
    }

    private async bool physical_source (string? name) {
        return (yield source_info (name)).physical;
    }

    private async bool physical_sink (string? name) {
        return (yield sink_info (name)).physical;
    }

    private async bool set_default (string name, bool input, string expected) {
        string? previous_source;
        string? previous_sink;
        if (!(yield server_defaults (out previous_source, out previous_sink))) {
            return false;
        }

        var previous = input ? previous_source : previous_sink;
        if (previous == name) {
            return true;
        }
        if (previous != expected) {
            return false;
        }

        bool success = false;
        PulseAudio.Context.SuccessCb callback = (c, result) => { success = result == 1; };
        var operation = input ? context.set_default_source (name, callback) : context.set_default_sink (name, callback);
        if (!(yield wait (operation)) || !success) {
            return false;
        }

        // The server subscription observes PipeWire's effective default,
        // which may follow the operation acknowledgement. No polling.
        bool expired = false;
        ulong handler = defaults_changed.connect (() => set_default.callback ());
        var deadline = new TimeoutSource (2000);
        deadline.set_callback (() => {
            expired = true;
            set_default.callback ();
            return Source.REMOVE;
        });
        deadline.attach ();
        while (!expired) {
            var current = input ? observed_source : observed_sink;
            if (current == name || current != (input ? previous_source : previous_sink)) {
                break;
            }
            yield;
        }
        deadline.destroy ();
        disconnect (handler);
        return !expired && (input ? observed_source : observed_sink) == name;
    }

    private async bool endpoints_available () {
        var source = yield source_info (SOURCE_NAME);
        var sink = yield sink_info (SINK_NAME);
        return source.complete && sink.complete && !source.exists && !sink.exists;
    }

    private async bool owns_endpoints (bool allow_missing = false) {
        var source = yield source_info (SOURCE_NAME);
        var sink = yield sink_info (SINK_NAME);
        source_index = source.is_owned ? source.index : PulseAudio.INVALID_INDEX;
        sink_index = sink.is_owned ? sink.index : PulseAudio.INVALID_INDEX;
        return source.complete && sink.complete &&
            (source.is_owned || (allow_missing && !source.exists)) &&
            (sink.is_owned || (allow_missing && !sink.exists));
    }

    private async bool restore_default (string? master, bool input) {
        var valid = input ? (yield physical_source (master)) : (yield physical_sink (master));
        if (!valid) {
            return true;
        }

        string? source;
        string? sink;
        if (!(yield server_defaults (out source, out sink))) {
            return false;
        }

        if ((input && source == SOURCE_NAME) || (!input && sink == SINK_NAME)) {
            return yield set_default (master, input, input ? SOURCE_NAME : SINK_NAME);
        }

        return true;
    }

    private async bool restore_streams () {
        // Unknown or foreign ownership must never authorize stream teardown.
        if (!(yield owns_endpoints (true))) {
            return false;
        }
        uint32[] recordings = {};
        uint32[] playbacks = {};
        bool success = true;
        var operation = context.get_source_output_info_list ((c, info, eol) => {
            if (eol < 0) {
                success = false;
            } else if (info != null && info.source == source_index && info.owner_module != module_index) {
                recordings += info.index;
            }
        });
        if (!(yield wait (operation)) || !success) {
            return false;
        }

        operation = context.get_sink_input_info_list ((c, info, eol) => {
            if (eol < 0) {
                success = false;
            } else if (info != null && info.sink == sink_index && info.owner_module != module_index) {
                playbacks += info.index;
            }
        });
        if (!(yield wait (operation)) || !success) {
            return false;
        }

        string? source;
        string? sink;
        if (!(yield server_defaults (out source, out sink))) {
            return false;
        }

        var target_source = (yield physical_source (source_master)) ? source_master : source;
        var target_sink = (yield physical_sink (sink_master)) ? sink_master : sink;
        if ((recordings.length > 0 && !(yield physical_source (target_source))) ||
            (playbacks.length > 0 && !(yield physical_sink (target_sink)))) {
            return false;
        }

        // Rescue only streams on our endpoints. Refuse to tear them down if
        // the server cannot move them (for example, PA_STREAM_DONT_MOVE).
        foreach (var index in recordings) {
            success = false;
            operation = context.move_source_output_by_name (
                index, target_source, (c, result) => { success = result == 1; }
            );
            if (!(yield wait (operation)) || !success) {
                return false;
            }
            remember_stream (true, index, target_source);
        }

        foreach (var index in playbacks) {
            success = false;
            operation = context.move_sink_input_by_name (index, target_sink, (c, result) => { success = result == 1; });
            if (!(yield wait (operation)) || !success) {
                return false;
            }
            remember_stream (false, index, target_sink);
        }

        return true;
    }

    private void remember_stream (bool input, uint32 index, string target) {
        RestoredStream[] streams = input ? restored_recordings : restored_playbacks;
        for (int i = 0; i < streams.length; i++) {
            if (streams[i].index == index) {
                streams[i].target = target;
                return;
            }
        }
        RestoredStream stream = { index, target };
        if (input) {
            restored_recordings += stream;
        } else {
            restored_playbacks += stream;
        }
    }

    private async bool reattach_streams (bool input) {
        if (!(yield owns_endpoints ())) {
            return false;
        }
        RestoredStream[] streams = input ? restored_recordings : restored_playbacks;
        foreach (var stream in streams) {
            var physical = input ? (yield source_info (stream.target)) : (yield sink_info (stream.target));
            if (!physical.complete) {
                return false;
            }
            bool still_restored = false;
            var operation = input ? context.get_source_output_info (stream.index, (c, info) => {
                if (info != null) still_restored = physical.exists && info.source == physical.index;
            }) : context.get_sink_input_info (stream.index, (c, info) => {
                if (info != null) still_restored = physical.exists && info.sink == physical.index;
            });
            if (!(yield wait (operation)) && context.errno () != PulseAudio.Error.NOENTITY) {
                return false;
            }
            // A closed stream or an external routing change is not ours to undo.
            if (!still_restored) {
                continue;
            }
            if (!settings.get_boolean ("echo-cancellation") || !(yield owns_endpoints ())) {
                return false;
            }
            bool success = false;
            operation = input ? context.move_source_output_by_name (stream.index, SOURCE_NAME,
                (c, result) => { success = result == 1; }) : context.move_sink_input_by_name (stream.index, SINK_NAME,
                (c, result) => { success = result == 1; });
            if (!(yield wait (operation)) || !success) {
                return false;
            }
        }
        if (input) {
            restored_recordings = {};
        } else {
            restored_playbacks = {};
        }
        return true;
    }

    private async bool release () {
        if (module_index == PulseAudio.INVALID_INDEX) {
            enabled = false;
            source_master = sink_master = null;
            return true;
        }

        // Only restore defaults still pointing at our filter. An external
        // device selection takes precedence. Never write volumes or stream
        // restore entries, or move streams attached to other endpoints.
        if (!(yield restore_streams ()) || !(yield restore_default (source_master, true)) ||
            !(yield restore_default (sink_master, false))) {
            return false;
        }

        bool success = false;
        var operation = context.unload_module (module_index, (c, result) => { success = result == 1; });
        if (!(yield wait (operation)) || (!success && module_index != PulseAudio.INVALID_INDEX)) {
            return false;
        }

        module_index = PulseAudio.INVALID_INDEX;
        source_master = sink_master = null;
        enabled = false;
        if (!settings.get_boolean ("echo-cancellation")) {
            restored_recordings = {};
            restored_playbacks = {};
        }
        // Unload acknowledgement can precede removal of the published endpoints.
        return yield await_endpoints (false);
    }

    private async bool await_endpoints (bool present = true) {
        bool expired = false;
        bool changed = false;
        bool waiting = false;
        ulong handler = endpoints_changed.connect (() => {
            changed = true;
            if (waiting) {
                await_endpoints.callback ();
            }
        });
        var deadline = new TimeoutSource (2000);
        deadline.set_callback (() => {
            expired = true;
            if (waiting) {
                await_endpoints.callback ();
            }
            return Source.REMOVE;
        });
        deadline.attach ();
        bool ready = false;
        while (!expired) {
            changed = false;
            var source = yield source_info (SOURCE_NAME);
            var sink = yield sink_info (SINK_NAME);
            if (!source.complete || !sink.complete || (present &&
                ((source.exists && !source.is_owned) || (sink.exists && !sink.is_owned)))) {
                break;
            }
            if (present ? source.is_owned && sink.is_owned : !source.exists && !sink.exists) {
                ready = !expired;
                break;
            }
            if (!changed && !expired) {
                waiting = true;
                yield;
                waiting = false;
            }
        }
        deadline.destroy ();
        disconnect (handler);
        return ready;
    }

    private async bool activate (string source, string sink, out bool selection_changed) {
        selection_changed = false;
        string? current_source = null;
        string? current_sink = null;
        // PipeWire can acknowledge the module before publishing its Pulse
        // endpoints. Wait for subscription events, with the same ownership gate.
        if (!(yield await_endpoints ()) || !(yield owns_endpoints ()) ||
            !(yield server_defaults (out current_source, out current_sink)) ||
            !settings.get_boolean ("echo-cancellation")) {
            return false;
        }

        if ((current_source != source && current_source != SOURCE_NAME) ||
            (current_sink != sink && current_sink != SINK_NAME)) {
            selection_changed = true;
            return false;
        }

        var sink_selected = yield set_default (SINK_NAME, false, sink);
        if (!(yield server_defaults (out current_source, out current_sink))) {
            return false;
        }

        selection_changed = (current_source != source && current_source != SOURCE_NAME) ||
            (current_sink != sink && current_sink != SINK_NAME);
        if (!sink_selected || selection_changed || !settings.get_boolean ("echo-cancellation")) {
            return false;
        }

        var source_selected = yield set_default (SOURCE_NAME, true, source);
        if (!source_selected && (yield server_defaults (out current_source, out current_sink))) {
            selection_changed = current_source != source && current_source != SOURCE_NAME;
        }

        return source_selected && (yield reattach_streams (true)) && (yield reattach_streams (false));
    }

    private async void reconcile () {
        reconciling = true;
        busy = true;
        pending = false;
        string? source = null;
        string? sink = null;
        // Rediscover before trusting absence, including after canceled loads
        // and MODULE NEW events. The same serialized, bounded path owns cleanup.
        if ((module_index != PulseAudio.INVALID_INDEX || (yield discover_module ())) &&
            (yield server_defaults (out source, out sink))) {
            enabled = module_index != PulseAudio.INVALID_INDEX && source == SOURCE_NAME && sink == SINK_NAME;
            var target_source = source == SOURCE_NAME ? source_master : source;
            var target_sink = sink == SINK_NAME ? sink_master : sink;
            available = (yield physical_source (target_source)) && (yield physical_sink (target_sink));
            if (restore_failed) {
                // Still discover and release a load that completed after timeout.
                yield release ();
            } else if (!settings.get_boolean ("echo-cancellation") || !available) {
                if (!(yield release ())) {
                    error = _("Could not disable echo cancellation.");
                } else {
                    error = !available && settings.get_boolean ("echo-cancellation") ?
                        _("Connect a microphone and an audio output to use echo cancellation.") : null;
                }
            } else if (module_index != PulseAudio.INVALID_INDEX &&
                       source_master == target_source && sink_master == target_sink &&
                       source == SOURCE_NAME && sink == SINK_NAME && (yield owns_endpoints ())) {
                if ((yield reattach_streams (true)) && (yield reattach_streams (false))) {
                    enabled = true;
                    error = null;
                } else {
                    error = _("Could not enable echo cancellation.");
                }
            } else if (yield release ()) {
                if (!(yield endpoints_available ())) {
                    error = _("The echo cancellation device names are already in use.");
                    if (context.get_state () == PulseAudio.Context.State.READY) {
                        enable_failed ();
                    }
                    reconciling = false;
                    refresh ();
                    return;
                }

                uint32 loaded_index = PulseAudio.INVALID_INDEX;
                var operation = context.load_module (
                    "module-echo-cancel", arguments (target_source, target_sink),
                    (c, index) => { loaded_index = index; }
                );
                if ((yield wait (operation)) && loaded_index != PulseAudio.INVALID_INDEX) {
                    module_index = loaded_index;
                    source_master = target_source;
                    sink_master = target_sink;
                    // A load may complete after a newer disable request.
                    if (!settings.get_boolean ("echo-cancellation")) {
                        yield release ();
                    } else {
                        bool selection_changed;
                        if (yield activate (target_source, target_sink, out selection_changed)) {
                            enabled = true;
                            error = null;
                        } else {
                            yield release ();
                            if (selection_changed) {
                                pending = true;
                            } else if (settings.get_boolean ("echo-cancellation")) {
                                error = _("Could not enable echo cancellation.");
                                if (context.get_state () == PulseAudio.Context.State.READY) {
                                    enable_failed ();
                                }
                            }
                        }
                    }
                } else {
                    error = _("Echo cancellation is not available on this audio server.");
                    if (context.get_state () == PulseAudio.Context.State.READY) {
                        // Cancelling a client operation does not cancel the
                        // server command. Discover and release a late load.
                        yield discover_module ();
                        yield release ();
                        enable_failed ();
                    }
                }
            } else {
                error = _("Could not update echo cancellation.");
            }
        } else {
            available = false;
            enabled = false;
            error = _("Could not connect to the audio server.");
            if (context.get_state () == PulseAudio.Context.State.READY && refresh_id == 0) {
                refresh_id = Timeout.add_seconds (2, () => {
                    refresh_id = 0;
                    refresh ();
                    return Source.REMOVE;
                });
            }
        }

        reconciling = false;
        if (pending && context.get_state () == PulseAudio.Context.State.READY) {
            refresh ();
        } else {
            busy = false;
        }
    }
}

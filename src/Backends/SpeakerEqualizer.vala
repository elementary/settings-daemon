/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 elementary, Inc. (https://elementary.io)
 */

internal class SettingsDaemon.Backends.SpeakerEqualizer : Object {

    public signal void changed ();
    private PulseAudio.Context context;
    private Wp.Core? core;
    private uint32? server_cookie;
    private Wp.ObjectManager? native_nodes;
    private Wp.Node? native_node;
    private string native_name = "";
    private string native_error = "";
    private enum NativeState {
        UNBOUND,
        WAITING_FOR_AUDIO,
        AUDITING,
        CONFIRMED,
        FAILED
    }

    private NativeState state;
    private uint native_revision;
    private uint native_idle;
    private uint connect_deadline;
    private ulong disconnected_handler;
    private ulong params_handler;
    private ulong state_handler;
    private bool native_busy;
    private bool native_pending;
    private bool may_write;
    private double[] target_gains;
    private bool target_enabled;
    private Settings? settings;
    private Profile? profile;
    private string settings_path = "";
    private string node = "";
    private string route = "";
    private string error = "";
    private string? echo_master;
    private bool eligible;
    private bool retiring;
    private bool stopped;
    private bool querying;
    private bool pending;
    private uint generation;
    private uint refresh_id;
    private uint reconnect_id;
    private Request? last_request;

    public SpeakerEqualizer (PulseAudio.Context context) {
        this.context = context;
    }

    public void reconnect (PulseAudio.Context context) {
        this.context = context;
        stopped = false;
        // A surviving native graph is audited, never overwritten on reconnect.
        may_write = false;
        if (state != NativeState.FAILED) {
            state = NativeState.UNBOUND;
        }
    }

    public Audio.EqualizerStatus get_status () {
        return {
            eligible && profile != null && (state != NativeState.UNBOUND || pending || querying || error != ""),
            querying || pending || native_busy || native_pending,
            eligible && !querying && !pending && !native_busy && !native_pending && state == NativeState.CONFIRMED,
            error != "" ? error : native_error,
            settings_path, node, route,
            profile != null ? profile.frequencies : new double[0],
            profile != null ? profile.types : new string[0],
            profile != null ? profile.defaults : new double[0],
            profile != null ? profile.minimum : new double[0],
            profile != null ? profile.maximum : new double[0]
        };
    }

    public void refresh (string? current_echo_master) {
        if (stopped) {
            return;
        }
        echo_master = current_echo_master;
        generation++;
        pending = true;
        if (refresh_id == 0 && !querying) {
            refresh_id = Timeout.add (100, () => {
                refresh_id = 0;
                reconcile.begin ();
                return Source.REMOVE;
            });
        }
        changed ();
    }

    private void settings_changed () {
        refresh (echo_master);
    }

    private void invalidate () {
        eligible = retiring = false;
        last_request = null;
        native_revision++;
        may_write = native_pending = false;
        state = NativeState.UNBOUND;
    }

    private void native_failed (string message) {
        may_write = native_pending = false;
        state = NativeState.FAILED;
        native_error = message;
        changed ();
        if (retiring) {
            refresh (echo_master);
        }
    }

    private void unbind () {
        if (native_node == null) {
            return;
        }
        native_node.disconnect (params_handler);
        native_node.disconnect (state_handler);
        native_node = null;
    }

    private void close_native () {
        native_revision++;
        if (connect_deadline != 0) {
            Source.remove (connect_deadline);
        }
        connect_deadline = 0;
        unbind ();
        native_nodes = null;
        if (core != null) {
            SignalHandler.disconnect (core, disconnected_handler);
            core.disconnect ();
        }
        core = null;
    }

    private void connection_lost () {
        may_write = false;
        state = NativeState.FAILED;
        native_error = _("The PipeWire equalizer connection failed.");
        native_pending = false;
        close_native ();
        changed ();
        if (!stopped && reconnect_id == 0) {
            reconnect_id = Timeout.add_seconds (2, () => {
                reconnect_id = 0;
                state = NativeState.UNBOUND;
                refresh (echo_master);
                return Source.REMOVE;
            });
        }
    }

    public void stop () {
        stopped = true;
        may_write = pending = false;
        generation++;
        if (refresh_id != 0) {
            Source.remove (refresh_id);
        }
        refresh_id = 0;
        if (reconnect_id != 0) {
            Source.remove (reconnect_id);
        }
        reconnect_id = 0;
        if (settings != null) {
            settings.changed.disconnect (settings_changed);
        }
        settings = null;
        close_native ();
        if (native_idle != 0) {
            Source.remove (native_idle);
        }
        native_idle = 0;
        eligible = false;
    }

    private async bool wait (PulseAudio.Operation? operation) {
        if (operation == null) {
            return false;
        }
        if (operation.get_state () != RUNNING) {
            return operation.get_state () == DONE;
        }
        bool expired = false;
        var timeout = new TimeoutSource (2000);
        timeout.set_callback (() => {
            expired = true;
            operation.cancel ();
            wait.callback ();
            return Source.REMOVE;
        });
        PulseAudio.operation_set_state_callback (operation, (op) => {
            if (!expired && op.get_state () != RUNNING) {
                timeout.destroy ();
                wait.callback ();
            }
        });
        timeout.attach ();
        yield;
        PulseAudio.operation_set_state_callback (operation, null);
        return !expired && operation.get_state () == DONE;
    }

    private async void reconcile () {
        querying = true;
        pending = false;
        uint request = generation;
        string? selected = null;
        bool pipewire = false;
        var op = context.get_server_info ((c, info) => {
            if (info != null) {
                selected = info.default_sink_name;
                pipewire = info.server_name != null && info.server_name.contains ("PipeWire");
            }
        });
        bool complete = yield wait (op);
        if (stopped || request != generation) {
            finish ();
            return;
        }
        if (!complete || !pipewire || selected == null) {
            invalidate ();
            error = _("Speaker equalization requires PipeWire and a supported physical output.");
            close_native ();
            finish ();
            return;
        }
        if (selected == EchoProcessor.SINK_NAME) {
            selected = echo_master;
        }
        if (retiring && (state == NativeState.CONFIRMED || state == NativeState.FAILED) && !native_busy) {
            node = "";
            close_native ();
            invalidate ();
        }
        // Remove our graph from the old physical output before following
        // another default, including its shared speaker/headphone route.
        bool release = selected != null && node != "" && selected != node;
        if (node != "") {
            selected = node;
        }
        if (selected == null) {
            invalidate ();
            finish ();
            return;
        }
        string? name = null, serial = null, device = null, profile_id = null, port = null;
        bool physical = false;
        string[] ports = {};
        bool ended = false;
        op = context.get_sink_info_by_name (selected, (c, info, eol) => {
            if (eol != 0) {
                ended = eol > 0;
            }
            if (info == null) {
                return;
            }
            physical = info.proplist.gets ("device.class") != "filter" &&
                info.proplist.gets ("node.virtual") != "true" &&
                info.proplist.gets ("device.master_device") == null &&
                (PulseAudio.SinkFlags.HARDWARE in info.flags || info.card != PulseAudio.INVALID_INDEX);
            name = info.name;
            serial = info.proplist.gets ("object.serial");
            device = info.proplist.gets ("device.id");
            profile_id = info.proplist.gets ("elementary.eq.profile");
            port = info.active_port != null ? info.active_port.name : "";
            foreach (var candidate in info.ports) {
                if (candidate != null) {
                    ports += candidate.name;
                }
            }
        });
        complete = yield wait (op);
        if (stopped || request != generation) {
            finish ();
            return;
        }
        error = "";
        if (!complete || !ended || !physical || name == null || serial == null || device == null ||
            profile_id == null || port == null) {
            if (node != "") {
                node = "";
                close_native ();
                refresh (echo_master);
            }
            invalidate ();
            error = _("No speaker equalizer profile is available for this output.");
            finish ();
            return;
        }
        bool valid_profile = false;
        try {
            var selected_profile = new Profile (profile_id, name, port);
            bool valid_route = port == "" ? ports.length == 0 : port in ports;
            if ((!valid_route && node == "") ||
                (profile_id != "generic-speakers-v1" && !(selected_profile.route in ports))) {
                node = "";
                close_native ();
                invalidate ();
                error = _("No speaker equalizer profile is available for this output.");
                if (release) {
                    refresh (echo_master);
                }
                finish ();
                return;
            }
            // Speaker recommendations belong only to their declared route.
            // Other routes use the same validated graph with neutral defaults.
            string preferences_profile = profile_id;
            if (profile_id != "generic-speakers-v1" && port != selected_profile.route) {
                selected_profile.route = port;
                selected_profile.defaults = {};
                preferences_profile = profile_id + "-neutral";
            }
            // Preferences are stable across transient PW IDs, scoped to the
            // installed profile revision, physical node name and selected route.
            string identity = Checksum.compute_for_string (ChecksumType.SHA256,
                preferences_profile + "\n" + name + "\n" + selected_profile.route);
            string path = valid_route ?
                "/io/elementary/settings-daemon/audio/equalizer/%s/".printf (identity) : settings_path;
            if (settings_path != path || settings == null) {
                if (settings != null) {
                    settings.changed.disconnect (settings_changed);
                }
                settings = new Settings.with_path ("io.elementary.settings-daemon.audio.equalizer", path);
                settings.changed.connect (settings_changed);
                settings_path = path;
            }
            profile = selected_profile;
            valid_profile = true;
            node = name;
            route = port;
            eligible = valid_route && port == profile.route && !release;
            if (!valid_route) {
                error = _("The selected output has no active route.");
            }
            var saved_enabled = settings.get_user_value ("enabled");
            bool requested = saved_enabled != null ? saved_enabled.get_boolean () :
                profile.defaults.length == 5 && settings.get_boolean ("enabled");
            bool enabled = eligible && requested;
            var stored = settings.get_user_value ("gains");
            if (stored == null) {
                var builder = new VariantBuilder (new VariantType ("ad"));
                double[] defaults = profile.defaults.length == 5 ? profile.defaults : new double[5];
                foreach (double gain in defaults) {
                    builder.add ("d", gain);
                }
                stored = builder.end ();
            }
            var gains = new double[5];
            if (enabled) {
                if (stored.n_children () != 5) {
                    throw new IOError.INVALID_DATA (_("Five equalizer gains are required."));
                }
                for (int i = 0; i < 5; i++) {
                    gains[i] = stored.get_child_value (i).get_double ();
                }
                for (int i = 0; i < 5; i++) {
                    if (!gains[i].is_finite () || gains[i] < profile.minimum[i] || gains[i] > profile.maximum[i]) {
                        throw new IOError.INVALID_DATA (_("An equalizer gain is outside the device profile range."));
                    }
                }
            }
            var desired = new Request () {
                node = name,
                serial = serial,
                device = device,
                profile = profile_id,
                route = port,
                signature = profile.signature,
                enabled = requested,
                valid_route = valid_route,
                gains = stored
            };
            ensure_native ();
            // Only changed identity/profile/preferences authorize an attempt.
            // Rediscovery, notifications, idle/resume and reconnect only audit.
            if (last_request == null || !last_request.matches (desired) || retiring != release) {
                last_request = desired;
                target_gains = gains;
                target_enabled = enabled;
                native_revision++;
                retiring = release;
                may_write = true;
                state = NativeState.UNBOUND;
                native_error = "";
            }
            queue_native ();

        } catch (Error e) {
            if (!valid_profile) {
                invalidate ();
                node = "";
                close_native ();
                if (release) {
                    refresh (echo_master);
                }
            } else {
                // A corrected preference may equal the last valid request.
                last_request = null;
                native_failed (e.message);
            }
            error = e.message;
        }
        finish ();
    }

    private void finish () {
        querying = false;
        changed ();
        if (pending && !stopped) {
            refresh (echo_master);
        }
    }

    private void ensure_native () {
        if (core != null && native_name != node) {
            close_native ();
        }
        if (core != null) {
            return;
        }
        Wp.init (Wp.InitFlags.PIPEWIRE | Wp.InitFlags.SPA_TYPES);
        native_name = node;
        core = new Wp.Core (null, null, null);
        disconnected_handler = core.disconnected.connect (connection_lost);
        native_nodes = new Wp.ObjectManager ();
        var interest = new Wp.ObjectInterest.type (typeof (Wp.Node));
        interest.add_constraint (Wp.ConstraintType.PW_GLOBAL_PROPERTY, "node.name",
            Wp.ConstraintVerb.EQUALS, new Variant.string (node));
        native_nodes.add_interest_full ((owned) interest);
        native_nodes.request_object_features (typeof (Wp.Node), (Wp.ObjectFeatures)
            (Wp.ProxyFeatures.PIPEWIRE_OBJECT_FEATURES_MINIMAL | Wp.ProxyFeatures.PIPEWIRE_OBJECT_FEATURE_PARAM_PROPS));
        native_nodes.objects_changed.connect (() => {
            native_revision++;
            queue_native ();
        });
        native_nodes.object_removed.connect ((obj) => {
            if (obj == native_node) {
                unbind ();
                state = NativeState.UNBOUND;
            }
        });
        native_nodes.installed.connect (() => {
            uint32 cookie = core.get_remote_cookie ();
            // Object serials can repeat in a new server; its graphs cannot survive.
            if (server_cookie != null && server_cookie != cookie) {
                native_revision++;
                may_write = true;
                state = NativeState.UNBOUND;
                native_error = "";
            }
            server_cookie = cookie;
            if (connect_deadline != 0) {
                Source.remove (connect_deadline);
            }
            connect_deadline = 0;
            queue_native ();
        });
        core.install_object_manager (native_nodes);
        connect_deadline = Timeout.add (2000, () => {
            connect_deadline = 0;
            connection_lost ();
            return Source.REMOVE;
        });
        if (!core.connect ()) {
            connection_lost ();
        }
    }

    private void queue_native () {
        if (stopped || last_request == null || state == NativeState.FAILED) {
            return;
        }
        native_pending = true;
        if (!native_busy && native_idle == 0) {
            native_idle = Idle.add (() => {
                native_idle = 0;
                audit_native.begin ();
                return Source.REMOVE;
            });
        }
        changed ();
    }

    private bool current (uint revision, Wp.Core owner) {
        return !stopped && revision == native_revision && owner == core && last_request != null;
    }

    private int control_slot (string name, ref uint64 mask) throws Error {
        if (!name.has_prefix ("eos_eq_")) {
            return -1;
        }
        string[] ports = { "Freq", "Q", "Gain", "b0", "b1", "b2", "a0", "a1", "a2" };
        int slot = name == "eos_eq_h:Mult" ? 45 : name == "eos_eq_h:Add" ? 46 : name == "eos_eq_h:Control" ? 47 : -1;
        for (int band = 0; band < 5; band++) {
            for (int port = 0; port < ports.length; port++) {
                if (name == "eos_eq_%d:%s".printf (band + 1, ports[port])) {
                    slot = band * 9 + port;
                }
            }
        }
        if (slot < 0 || (mask & (1UL << slot)) != 0) {
            throw new IOError.INVALID_DATA (_("Equalizer controls are malformed or duplicated."));
        }
        mask |= 1UL << slot;
        return slot;
    }

    private float[]? controls (Wp.Iterator? parameters, bool metadata) throws Error {
        uint64 mask = 0;
        var values = new float[48];
        uint blocks = 0;
        uint graphs = 0;
        if (parameters == null) {
            throw new IOError.INVALID_DATA (_("The installed equalizer controls are incomplete."));
        }
        Value item;
        while (parameters.next (out item)) {
            blocks++;
            unowned Wp.SpaPod pod = (Wp.SpaPod) item.get_boxed ();
            var properties = pod.new_iterator ();
            bool device_properties = false;
            Value entry;
            while (properties.next (out entry)) {
                unowned Wp.SpaPod property = (Wp.SpaPod) entry.get_boxed ();
                unowned string key;
                Wp.SpaPod value;
                if (!property.get_property (out key, out value)) {
                    break;
                }
                if (!metadata && (key == "volume" || key == "device")) {
                    device_properties = true;
                }
                if (metadata && key == "name") {
                    unowned string name;
                    if (value.get_string (out name)) {
                        control_slot (name, ref mask);
                    }
                } else if (!metadata && key == "params" && value.is_struct ()) {
                    var params = value.new_iterator ();
                    Value k, v;
                    while (params.next (out k)) {
                        unowned string name;
                        if (!params.next (out v)) {
                            throw new IOError.INVALID_DATA (_("Equalizer controls are malformed or duplicated."));
                        }
                        if (!((Wp.SpaPod) k.get_boxed ()).get_string (out name)) {
                            throw new IOError.INVALID_DATA (_("Equalizer controls are malformed or duplicated."));
                        }
                        int slot = control_slot (name, ref mask);
                        if (slot >= 0 && (!((Wp.SpaPod) v.get_boxed ()).get_float (out values[slot]) || !values[slot].is_finite ())) {
                            throw new IOError.INVALID_DATA (_("Equalizer controls are malformed or duplicated."));
                        }
                    }
                }
            }
            if (!metadata && !device_properties) {
                graphs++;
            }
        }
        // Audioconvert and ALSA expose their own Props as well as graph controls.
        // A graph without controls still occupies a slot and must be preserved.
        if (!metadata && (graphs > 1 || (graphs == 1 && mask == 0))) {
            throw new IOError.INVALID_DATA (_("Another application is processing this output."));
        }
        if (!metadata && blocks == 0) {
            throw new IOError.INVALID_DATA (_("The output controls are unavailable."));
        }
        if (mask == 0) {
            return null;
        }
        if (mask != (1UL << 48) - 1) {
            throw new IOError.INVALID_DATA (_("The installed equalizer controls are incomplete."));
        }
        return values;
    }

    private async void audit_native () {
        native_pending = false;
        if (core == null || native_nodes == null || last_request == null || state == NativeState.FAILED) {
            return;
        }
        native_busy = true;
        uint revision = native_revision;
        var owner = core;
        var desired = last_request;
        var installed = profile;
        var cancel = new Cancellable ();
        uint deadline = 0;
        try {
            var count = native_nodes.get_n_objects ();
            if (count == 0) {
                state = NativeState.UNBOUND;
                return;
            }
            if (count != 1) {
                throw new IOError.INVALID_DATA (_("The physical output name is not unique."));
            }
            var objects = native_nodes.new_iterator ();
            Value item;
            objects.next (out item);
            var selected = (Wp.Node) item.get_object ();
            var props = selected.get_properties ();
            if (props.get ("node.name") != desired.node ||
                props.get ("object.serial") != desired.serial ||
                props.get ("device.id") != desired.device ||
                props.get ("elementary.eq.profile") != desired.profile ||
                props.get ("media.class") != "Audio/Sink" || props.get ("node.virtual") == "true") {
                throw new IOError.INVALID_DATA (_("The physical output or its equalizer profile changed."));
            }
            if (native_node != selected) {
                unbind ();
                native_node = selected;
                params_handler = selected.params_changed.connect ((id) => {
                    if (id == "Props") {
                        queue_native ();
                    }
                });
                state_handler = selected.state_changed.connect (() => {
                    native_revision++;
                    queue_native ();
                });
            }
            if (selected.state != Wp.NodeState.RUNNING && target_enabled) {
                state = NativeState.WAITING_FOR_AUDIO;
                return;
            }
            state = NativeState.AUDITING;
            deadline = Timeout.add (2000, () => {
                deadline = 0;
                cancel.cancel ();
                if (core == owner) {
                    connection_lost ();
                }
                return Source.REMOVE;
            });
            var metadata = yield selected.enum_params ("PropInfo", null, cancel);
            if (!current (revision, owner)) {
                return;
            }
            var shape = controls (metadata, true);
            var parameters = yield selected.enum_params ("Props", null, cancel);
            if (!current (revision, owner)) {
                return;
            }
            var values = controls (parameters, false);
            bool attached = shape != null || values != null;
            if (attached) {
                if (shape == null || values == null) {
                    throw new IOError.INVALID_DATA (_("The installed equalizer controls are incomplete."));
                }
                for (int i = 0; i < 5; i++) {
                    if (Math.fabs (values[i * 9] - installed.frequencies[i]) > 0.01 ||
                        Math.fabs (values[i * 9 + 1] - installed.q[i]) > 0.0001) {
                        throw new IOError.INVALID_DATA (_("The equalizer does not match its installed profile."));
                    }
                }
                if (values[46] != 0 || values[47] != 0) {
                    throw new IOError.INVALID_DATA (_("The equalizer headroom control changed."));
                }
            }
            bool matches = attached == target_enabled;
            if (matches && attached) {
                matches = Math.fabs (values[45] - 1) <= 0.00001;
                for (int i = 0; i < 5; i++) {
                    matches &= Math.fabs (values[i * 9 + 2] - target_gains[i]) <= 0.001;
                }
            }
            if (!matches && !may_write) {
                throw new IOError.INVALID_DATA (_("The equalizer controls changed outside Sound settings."));
            }
            may_write = false;
            if (matches) {
                state = NativeState.CONFIRMED;
                native_error = "";
                if (retiring) {
                    refresh (echo_master);
                }
                return;
            }
            var params = new Wp.SpaPodBuilder.@struct ();
            if (attached != target_enabled) {
                params.add_string ("audioconvert.filter-graph.0");
                params.add_string (target_enabled ? installed.graph (target_gains) : "");
            } else {
                for (int i = 0; i < 5; i++) {
                    params.add_string ("eos_eq_%d:Gain".printf (i + 1));
                    params.add_float ((float) target_gains[i]);
                }
                params.add_string ("eos_eq_h:Mult");
                params.add_float (1.0f);
            }
            var setter = new Wp.SpaPodBuilder.object ("Spa:Pod:Object:Param:Props", "Props");
            setter.add_property ("params");
            setter.add_pod (params.end ());
            if (!selected.set_param ("Props", 0, setter.end ())) {
                throw new IOError.FAILED (_("PipeWire rejected the equalizer controls."));
            }
            yield owner.sync (cancel);
            // Confirm the write with a fresh enumeration, including after idle.
            if (current (revision, owner)) {
                native_pending = true;
            }
        } catch (Error e) {
            if (current (revision, owner)) {
                native_failed (e.message);
            }
        } finally {
            if (deadline != 0) {
                Source.remove (deadline);
            }
            native_busy = false;
            if (native_pending) {
                queue_native ();
            }
            changed ();
        }
    }

    private class Request : Object {
        public string node;
        public string serial;
        public string device;
        public string profile;
        public string route;
        public string signature;
        public bool enabled;
        public bool valid_route;
        public Variant gains;

        public bool matches (Request other) {
            return node == other.node && serial == other.serial && device == other.device &&
                profile == other.profile && route == other.route && signature == other.signature &&
                enabled == other.enabled && valid_route == other.valid_route && gains.equal (other.gains);
        }
    }

    private class Profile : Object {
        public string signature;
        public string node;
        public string route;
        public string[] types;
        public double[] frequencies;
        public double[] q;
        public double[] defaults;
        public double[] minimum;
        public double[] maximum;

        public string graph (double[] gains) {
            string[] filters = { "bq_lowshelf", "bq_peaking", "bq_peaking", "bq_peaking", "bq_highshelf" };
            var graph = new StringBuilder ("{ nodes = [");
            for (int i = 0; i < 5; i++) {
                graph.append_printf ("{ type = builtin name = eos_eq_%d label = %s " +
                    "control = { Freq = %s Q = %s Gain = %s } }",
                    i + 1, filters[i], frequencies[i].to_string (), q[i].to_string (), gains[i].to_string ());
            }
            graph.append ("{ type = builtin name = eos_eq_h label = linear " +
                "control = { Mult = 1 Add = 0 Control = 0 } } ] links = [");
            for (int i = 1; i < 5; i++) {
                graph.append_printf ("{ output = \"eos_eq_%d:Out\" input = \"eos_eq_%d:In\" }", i, i + 1);
            }
            graph.append ("{ output = \"eos_eq_5:Out\" input = \"eos_eq_h:In\" } ] }");
            return graph.str;
        }

        public Profile (string id, string output, string selected_route) throws Error {
            var file = new KeyFile ();
            string data = SpeakerEqualizerProfile.read (id);
            signature = Checksum.compute_for_string (ChecksumType.SHA256, data);
            file.load_from_data (data, data.length, KeyFileFlags.NONE);
            if (file.get_integer ("Profile", "Version") != 1 ||
                file.get_string ("Profile", "Namespace") != "eos_eq" ||
                !file.get_boolean ("Profile", "FirstGraph")) {
                throw new IOError.INVALID_DATA (_("The equalizer profile version or namespace is invalid."));
            }
            node = file.get_string ("Profile", "Node");
            route = file.get_string ("Profile", "Route");
            types = file.get_string_list ("Profile", "Types");
            frequencies = file.get_double_list ("Profile", "Frequencies");
            q = file.get_double_list ("Profile", "Q");
            defaults = file.get_double_list ("Profile", "DefaultGains");
            minimum = file.get_double_list ("Profile", "MinimumGains");
            maximum = file.get_double_list ("Profile", "MaximumGains");
            // The shipped generic layout has no OEM tuning. Its wildcard binds
            // to the same physical node checked by PulseAudio and PipeWire.
            bool generic = id == "generic-speakers-v1";
            if (generic && node == "*") {
                node = output;
            }
            if (generic && route == "*") {
                route = selected_route;
            }
            if (node == "" || node.length > 256 || (!generic && route == "") || route.length > 128 ||
                types.length != 5 || frequencies.length != 5 || q.length != 5 || defaults.length != (generic ? 0 : 5) ||
                minimum.length != 5 || maximum.length != 5) {
                throw new IOError.INVALID_DATA (_("The equalizer profile is incomplete."));
            }
            string[] layout_types = { "low-shelf", "peak", "peak", "peak", "high-shelf" };
            for (int i = 0; i < 5; i++) {
                if (types[i] != layout_types[i] ||
                    !frequencies[i].is_finite () || frequencies[i] < 20 || frequencies[i] > 20000 ||
                    !q[i].is_finite () || q[i] <= 0 || q[i] > 10 ||
                    !minimum[i].is_finite () || !maximum[i].is_finite () ||
                    minimum[i] < -24 || minimum[i] > 0 || maximum[i] < 0 || maximum[i] > 12 ||
                    (defaults.length == 5 && (!defaults[i].is_finite () ||
                        defaults[i] < minimum[i] || defaults[i] > maximum[i]))) {
                    throw new IOError.INVALID_DATA (_("An equalizer profile band is invalid."));
                }
            }
            if (node != output) {
                throw new IOError.INVALID_DATA (_("The equalizer profile does not match the physical output."));
            }
        }
    }
}

/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Backends.Schedule : Object {
    public enum Type {
        MANUAL,
        DAYLIGHT
    }

    public struct Parsed {
        string id;
        Type type;
        string name;
        bool enabled;
        HashTable<string, Variant> args;
        HashTable<string, Variant> active_settings;
        HashTable<string, Variant> inactive_settings;
    }

    public signal void apply_settings (HashTable<string, Variant> settings);

    private Parsed _parsed;
    public Parsed parsed {
        get { return _parsed; }
        set {
            _parsed = value;
            dirty = true;
        }
    }

    public string id { get { return parsed.id; } }
    public Type schedule_type { get { return parsed.type; } }
    public string name { get { return parsed.name; } }
    public bool enabled { get { return parsed.enabled; } }
    public HashTable<string, Variant> args { get { return parsed.args; } }
    public HashTable<string, Variant> active_settings { get { return parsed.active_settings; } }
    public HashTable<string, Variant> inactive_settings { get { return parsed.inactive_settings; } } //Inactive settings should usually be !active_settings but can also be e.g. a default wallpaper path

    private TimeTracker time_tracker;
    private bool active = false;
    private bool dirty = false;

    public Schedule (Parsed parsed) {
        Object (parsed: parsed);
    }

    construct {
        time_tracker = new TimeTracker ();
        Timeout.add (1000, time_callback);
    }

    private bool time_callback () {
        bool is_in = false;
        switch (schedule_type) {
            case MANUAL:
                if ("from" in args && "to" in args) {
                    is_in = time_tracker.is_in_time_window_manual (args["from"].get_double (), args["to"].get_double ());
                }
                break;

            case DAYLIGHT:
                is_in = time_tracker.is_in_time_window_daylight ();
                break;
        }

        if (dirty || active != is_in) {
            dirty = false;
            active = is_in;
            if (enabled) {
                apply_settings (active ? active_settings : inactive_settings);
            }
        }

        return Source.CONTINUE;
    }
}

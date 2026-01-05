/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Backends.FocusModes.Mode : Object {
    public enum Type {
        MANUAL,
        DAYLIGHT
    }

    public struct Parsed {
        string id;
        string name;
        bool enabled;
        bool active;
        HashTable<string, Variant> schedule;
        HashTable<string, Variant> settings;
    }

    private const string DARK_MODE = "dark-mode";
    private const string DND = "dnd";
    private const string MONOCHROME = "monochrome";

    private static HashTable<string, Setting> setting_handlers;

    static construct {
        setting_handlers = new HashTable<string, Setting> (str_hash, str_equal);

        setting_handlers[DARK_MODE] = new GLibSetting ("io.elementary.settings-daemon.prefers-color-scheme", "color-scheme", "prefer-dark");
        setting_handlers[DND] = new GLibSetting ("io.elementary.notifications", "do-not-disturb", true);
        setting_handlers[MONOCHROME] = new GLibSetting ("io.elementary.desktop.wm.accessibility", "enable-monochrome-filter", true);
    }

    private Parsed _parsed;
    public Parsed parsed {
        get { return _parsed; }
        set {
            if (is_active) {
                // If we're currently active unapply the old settings and reapply the new ones
                unapply_settings ();
                _parsed = value;
                apply_settings ();
            } else {
                _parsed = value;
            }

            check_triggers ();
        }
    }

    public string id { get { return parsed.id; } }
    public string name { get { return parsed.name; } }
    public bool enabled { get { return parsed.enabled; } }
    public bool active { get { return parsed.active; } set { _parsed.active = value; } }
    public HashTable<string, Variant> schedule { get { return parsed.schedule; } }
    public HashTable<string, Variant> settings { get { return parsed.settings; } }

    private TimeTracker time_tracker;
    private bool is_active = false;
    private bool user_override = false;

    public Mode (Parsed parsed) {
        Object (parsed: parsed);
    }

    construct {
        time_tracker = new TimeTracker ();
        Timeout.add_seconds (1, () => {
            check_triggers ();
            return Source.CONTINUE;
        });
    }

    private void check_triggers () {
        var is_in = false;

        if ("daylight" in schedule) {
            is_in = time_tracker.is_in_time_window_daylight ();
        } else if ("manual" in schedule && schedule["manual"].n_children () == 2) {
            var from_time = schedule["manual"].get_child_value (0).get_double ();
            var to_time = schedule["manual"].get_child_value (1).get_double ();
            is_in = time_tracker.is_in_time_window_manual (from_time, to_time);
        }

        if (active != is_active) {
            // The user toggled the mode manually
            user_override = true;
        }

        if (user_override && is_in == active) {
            // The schedule agrees with the user again so we disable the override and
            // use the schedule as the source of truth again
            user_override = false;
        }

        var should_activate = user_override ? active : is_in;

        if (should_activate && !is_active) {
            if (!active) {
                active = true;
            }

            apply_settings ();
        } else if (!should_activate && is_active) {
            if (active) {
                active = false;
            }

            unapply_settings ();
        }

        assert (user_override ^ active == is_in);
        assert (active == is_active);
    }

    private void apply_settings () requires (!is_active) {
        is_active = true;

        foreach (var key in settings.get_keys ()) {
            if (key in setting_handlers) {
                setting_handlers[key].apply (settings[key]);
            } else {
                warning ("Tried to apply unknown setting: %s", key);
            }
        }
    }

    private void unapply_settings () requires (is_active) {
        is_active = false;

        foreach (var key in settings.get_keys ()) {
            if (key in setting_handlers) {
                setting_handlers[key].unapply ();
            } else {
                warning ("Tried to unapply unknown setting: %s", key);
            }
        }
    }
}

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
        HashTable<string, Variant> args;
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

        //  setting_handlers[DARK_MODE] = new SettingsDaemon.Backends.Modes.Settings.ColorSchemeSetting ();
        //  setting_handlers[DND] = new SettingsDaemon.Backends.Modes.Settings.DNDSetting ();
        //  setting_handlers[MONOCHROME] = new SettingsDaemon.Backends.Modes.Settings.MonochromeSetting ();
    }

    private Parsed _parsed;
    public Parsed parsed {
        get { return _parsed; }
        set {
            if (is_active) {
                unapply_settings ();
            }

            _parsed = value;
            check_triggers ();
        }
    }

    public string id { get { return parsed.id; } }
    public string name { get { return parsed.name; } }
    public bool enabled { get { return parsed.enabled; } }
    private bool active { get { return parsed.active; } set { parsed.active = value; } }
    public HashTable<string, Variant> args { get { return parsed.args; } }
    public HashTable<string, Variant> settings { get { return parsed.settings; } }

    private TimeTracker time_tracker;
    private bool is_active = false;

    public Mode (Parsed parsed) {
        Object (parsed: parsed);
    }

    construct {
        time_tracker = new TimeTracker ();
    }

    private void check_triggers () {
        bool should_activate = active;
        //  switch (mode_type) {
        //      case MANUAL:
        //          if ("from" in args && "to" in args) {
        //              is_in = time_tracker.is_in_time_window_manual (args["from"].get_double (), args["to"].get_double ());
        //          }
        //          break;

        //      case DAYLIGHT:
        //          is_in = time_tracker.is_in_time_window_daylight ();
        //          break;
        //  }

        if (is_active != should_activate) {
            active = should_activate;

            if (enabled) {
                if (should_activate) {
                    apply_settings ();
                } else {
                    unapply_settings ();
                }
            }
        }
    }

    //  private void apply_settings (HashTable<string, Variant> settings) {
    //      foreach (var key in settings.get_keys ()) {
    //          switch (key) {
    //              case DARK_MODE:
    //                  var scheme = ((bool) settings[DARK_MODE]) ? Granite.Settings.ColorScheme.DARK : Granite.Settings.ColorScheme.LIGHT;
    //                  color_scheme_settings.set_enum ("color-scheme", scheme);
    //                  break;
    //              case DND:
    //                  dnd_settings.set_boolean ("do-not-disturb", (bool) settings[DND]);
    //                  break;
    //              case MONOCHROME:
    //                  monochrome_settings.set_boolean ("enable-monochrome-filter", (bool) settings[MONOCHROME]);
    //                  break;
    //              default:
    //                  warning ("Tried to apply unknown setting: %s", key);
    //                  break;
    //          }
    //      }
    //  }
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

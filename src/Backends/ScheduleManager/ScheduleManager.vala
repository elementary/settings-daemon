/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

[DBus (name="io.elementary.settings_daemon.ScheduleManager")]
public class SettingsDaemon.Backends.ScheduleManager : GLib.Object {
    private const string DARK_MODE = "dark-mode";
    private const string DND = "dnd";
    private const string MONOCHROME = "monochrome";

    private static Settings settings = new Settings ("io.elementary.settings-daemon.schedules");
    private static Settings color_scheme_settings = new Settings ("io.elementary.settings-daemon.prefers-color-scheme");
    private static Settings dnd_settings = new Settings ("io.elementary.notifications");
    private static Settings monochrome_settings = new Settings ("io.elementary.desktop.wm.accessibility");

    public signal void items_changed (uint pos, uint removed, uint added);

    private HashTable<string, Schedule> schedules = new HashTable<string, Schedule> (str_hash, str_equal);
    private ListStore schedules_list;

    construct {
        schedules_list = new ListStore (typeof (Schedule));
        schedules_list.items_changed.connect ((pos, rem, add) => items_changed (pos, rem, add));

        foreach (var parsed_schedule in (Schedule.Parsed[]) settings.get_value ("schedules")) {
            add_schedule (parsed_schedule);
        }
    }

    private void add_schedule (Schedule.Parsed parsed) {
        var schedule = new Schedule (parsed);

        schedule.apply_settings.connect (apply_settings);

        schedules[schedule.id] = schedule;
        schedules_list.append (schedule);
    }

    public uint get_n_schedules () throws DBusError, IOError {
        return schedules_list.n_items;
    }

    public Schedule.Parsed get_schedule (uint pos) throws DBusError, IOError {
        return ((Schedule) schedules_list.get_item (pos)).parsed;
    }

    public void update_schedule (Schedule.Parsed parsed) throws DBusError, IOError {
        if (parsed.id in schedules) {
            schedules[parsed.id].parsed = parsed;
        } else {
            add_schedule (parsed);
        }

        save_schedules ();
    }

    public void delete_schedule (string id) throws DBusError, IOError {
        if (!(id in schedules)) {
            throw new IOError.NOT_FOUND ("Schedule with the same name not found");
        }

        uint pos;
        if (schedules_list.find (schedules[id], out pos)) {
            schedules_list.remove (pos);
        }

        schedules.remove (id);

        save_schedules ();
    }

    private void apply_settings (HashTable<string, Variant> settings) {
        foreach (var key in settings.get_keys ()) {
            switch (key) {
                case DARK_MODE:
                    var scheme = ((bool) settings[DARK_MODE]) ? Granite.Settings.ColorScheme.DARK : Granite.Settings.ColorScheme.LIGHT;
                    color_scheme_settings.set_enum ("color-scheme", scheme);
                    break;
                case DND:
                    dnd_settings.set_boolean ("do-not-disturb", (bool) settings[DND]);
                    break;
                case MONOCHROME:
                    monochrome_settings.set_boolean ("enable-monochrome-filter", (bool) settings[MONOCHROME]);
                    break;
                default:
                    warning ("Tried to apply unknown setting: %s", key);
                    break;
            }
        }
    }

    private void save_schedules () {
        Schedule.Parsed[] parsed_schedules = {};
        foreach (var schedule in schedules.get_values ()) {
            parsed_schedules += schedule.parsed;
        }

        settings.set_value ("schedules", parsed_schedules);
    }
}

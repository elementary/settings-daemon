/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

[DBus (name="io.elementary.settings_daemon.ModeManager")]
public class SettingsDaemon.Backends.FocusModes.Manager : GLib.Object {
    private static Settings settings = new Settings ("io.elementary.settings-daemon.focus-modes");

    public signal void items_changed (uint pos, uint removed, uint added);
    public signal void properties_changed (uint pos);

    private HashTable<string, Mode> modes = new HashTable<string, Mode> (str_hash, str_equal);
    private ListStore modes_list;

    construct {
        modes_list = new ListStore (typeof (Mode));
        modes_list.items_changed.connect ((pos, rem, add) => items_changed (pos, rem, add));

        foreach (var parsed_mode in (Mode.Parsed[]) settings.get_value ("focus-modes")) {
            add_mode (parsed_mode);
        }
    }

    public uint get_n_modes () throws DBusError, IOError {
        return modes_list.n_items;
    }

    public Mode.Parsed get_mode (uint pos) throws DBusError, IOError {
        return ((Mode) modes_list.get_item (pos)).parsed;
    }

    public void update_mode (Mode.Parsed parsed) throws DBusError, IOError {
        if (parsed.id in modes) {
            modes[parsed.id].parsed = parsed;
        } else {
            add_mode (parsed);
        }

        save_modes ();
    }

    private void add_mode (Mode.Parsed parsed) {
        var mode = new Mode (parsed);

        mode.notify.connect (on_mode_notify);

        modes[mode.id] = mode;
        modes_list.append (mode);
    }

    private void on_mode_notify (Object obj, ParamSpec pspec) requires (obj is Mode) {
        var mode = (Mode) obj;

        uint pos;
        if (modes_list.find (mode, out pos)) {
            properties_changed (pos);
        } else {
            warning ("Unknown mode notified");
        }
    }

    public void delete_mode (string id) throws DBusError, IOError {
        if (!(id in modes)) {
            throw new IOError.NOT_FOUND ("Mode with the same name not found");
        }

        uint pos;
        if (modes_list.find (modes[id], out pos)) {
            modes_list.remove (pos);
        }

        modes.remove (id);

        save_modes ();
    }

    private void save_modes () {
        Mode.Parsed[] parsed_modes = {};
        foreach (var mode in modes.get_values ()) {
            parsed_modes += mode.parsed;
        }

        settings.set_value ("focus-modes", parsed_modes);
    }
}

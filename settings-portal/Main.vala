/*-
 * Copyright 2021 elementary, Inc. <https://elementary.io>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor
 * Boston, MA 02110-1335 USA.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

private static bool opt_replace = false;
private static bool show_version = false;

private static GLib.MainLoop loop;

private const GLib.OptionEntry[] ENTRIES = {
    { "replace", 'r', 0, OptionArg.NONE, ref opt_replace, "Replace a running instance", null },
    { "version", 0, 0, OptionArg.NONE, ref show_version, "Show program version.", null },
    { null }
};

private void on_bus_acquired (GLib.DBusConnection connection, string name) {
    try {
        connection.register_object ("/org/freedesktop/portal/desktop", new SettingsDaemon.Settings ());
    } catch (GLib.Error e) {
        critical ("Unable to register the object: %s", e.message);
    }
}

public int main (string[] args) {
    var context = new GLib.OptionContext ("- Settings portal");
    context.add_main_entries (ENTRIES, null);
    try {
        context.parse (ref args);
    } catch (Error e) {
        printerr ("%s: %s", Environment.get_application_name (), e.message);
        printerr ("\n");
        printerr ("Try \"%s --help\" for more information.", GLib.Environment.get_prgname ());
        printerr ("\n");
        return 1;
    }

    if (show_version) {
      print ("%s \n", Build.VERSION);
      return 0;
    }

    loop = new GLib.MainLoop (null, false);

    try {
        var session_bus = GLib.Bus.get_sync (GLib.BusType.SESSION);
        var owner_id = GLib.Bus.own_name (
            GLib.BusType.SESSION,
            "org.freedesktop.impl.portal.desktop.elementary.settings-daemon",
            GLib.BusNameOwnerFlags.ALLOW_REPLACEMENT | (opt_replace ? GLib.BusNameOwnerFlags.REPLACE : 0),
            on_bus_acquired,
            () => { debug ("org.freedesktop.impl.portal.desktop.elementary.settings acquired"); },
            () => { loop.quit (); }
        );
        loop.run ();
        GLib.Bus.unown_name (owner_id);
    } catch (Error e) {
        printerr ("No session bus: %s\n", e.message);
        return 2;
    }

    return 0;

}

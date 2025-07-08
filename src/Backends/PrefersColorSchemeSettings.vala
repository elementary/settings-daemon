/*
* Copyright 2020–2021 elementary, Inc. (https://elementary.io)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 3 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Marius Meisenzahl <mariusmeisenzahl@gmail.com>
*/

public class SettingsDaemon.Backends.PrefersColorSchemeSettings : Object {
    public unowned Pantheon.AccountsService accounts_service { get; construct; }

    private const string COLOR_SCHEME = "color-scheme";

    private Settings color_settings;

    public PrefersColorSchemeSettings (Pantheon.AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        color_settings = new Settings ("io.elementary.settings-daemon.prefers-color-scheme");
        color_settings.changed[COLOR_SCHEME].connect (update_color_scheme);
    }

    private void update_color_scheme () {
        var color_scheme = color_settings.get_enum (COLOR_SCHEME);
        if (
            color_scheme == Granite.Settings.ColorScheme.DARK && !is_in_schedule () ||
            color_scheme != Granite.Settings.ColorScheme.DARK && is_in_schedule ()
        ) {
            color_settings.set_boolean (DARK_SCHEDULE_SNOOZED, true);
        }

        accounts_service.prefers_color_scheme = color_scheme;

        var mutter_settings = new GLib.Settings ("org.gnome.desktop.interface");
        mutter_settings.set_enum ("color-scheme", color_scheme);
    }
}

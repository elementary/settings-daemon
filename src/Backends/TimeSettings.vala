/*
* Copyright 2020 elementary, Inc. (https://elementary.io)
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
* Authored by: Marius Meisenzahl <mariusmeisenzahl@gmail.com>
*/

public class SettingsDaemon.Backends.TimeSettings : GLib.Object {
    public unowned AccountsService accounts_service { get; construct; }

    private GLib.Settings clock_settings;

    public TimeSettings (AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        clock_settings = new GLib.Settings ("org.gnome.desktop.interface");

        if (accounts_service.clock_format != clock_settings.get_string ("clock-format")) {
            sync_accountsservice_to_gsettings ();
        }

        sync_gsettings_to_accountsservice ();

        clock_settings.changed.connect ((key) => {
            if (key == "clock-format") {
                sync_gsettings_to_accountsservice ();
            }
        });
    }

    private void sync_accountsservice_to_gsettings () {
        clock_settings.set_string ("clock-format", accounts_service.clock_format);
    }

    private void sync_gsettings_to_accountsservice () {
        accounts_service.clock_format = clock_settings.get_string ("clock-format");
    }
}

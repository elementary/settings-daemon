/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
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
 */

public class SettingsDaemon.Backends.InterfaceSettings : GLib.Object {
    private const string CURSOR_BLINK = "cursor-blink";
    private const string CURSOR_BLINK_TIME = "cursor-blink-time";
    private const string CURSOR_BLINK_TIMEOUT = "cursor-blink-timeout";
    private const string CURSOR_SIZE = "cursor-size";
    private const string LOCATE_POINTER = "locate-pointer";
    private const string TEXT_SCALING_FACTOR = "text-scaling-factor";

    public unowned AccountsService accounts_service { get; construct; }

    private GLib.Settings interface_settings;

    public InterfaceSettings (AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        interface_settings = new GLib.Settings ("org.gnome.desktop.interface");

        // in case user changes text scaling in greeter session using a11y indicator
        if (accounts_service.text_scaling_factor != interface_settings.get_double (TEXT_SCALING_FACTOR)) {
            interface_settings.set_value (TEXT_SCALING_FACTOR, accounts_service.text_scaling_factor);
        }

        sync_gsettings_to_accountsservice ();

        interface_settings.changed.connect ((key) => {
            if (key == CURSOR_BLINK ||
                key == CURSOR_BLINK_TIME ||
                key == CURSOR_BLINK_TIMEOUT ||
                key == CURSOR_SIZE ||
                key == LOCATE_POINTER ||
                key == TEXT_SCALING_FACTOR) {
                sync_gsettings_to_accountsservice ();
            }
        });
    }

    private void sync_gsettings_to_accountsservice () {
        accounts_service.cursor_blink = interface_settings.get_boolean (CURSOR_BLINK);
        accounts_service.cursor_blink_time = interface_settings.get_int (CURSOR_BLINK_TIME);
        accounts_service.cursor_blink_timeout = interface_settings.get_int (CURSOR_BLINK_TIMEOUT);
        accounts_service.cursor_size = interface_settings.get_int (CURSOR_SIZE);
        accounts_service.locate_pointer = interface_settings.get_boolean (LOCATE_POINTER);
        accounts_service.text_scaling_factor = interface_settings.get_double (TEXT_SCALING_FACTOR);
    }
}

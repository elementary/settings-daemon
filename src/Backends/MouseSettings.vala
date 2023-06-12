/*
 * Copyright 2021 elementary, Inc. (https://elementary.io)
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

public class SettingsDaemon.Backends.MouseSettings : GLib.Object {
    public unowned AccountsService accounts_service { get; construct; }

    private GLib.Settings mouse_settings;
    private GLib.Settings touchpad_settings;

    public MouseSettings (AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        mouse_settings = new GLib.Settings ("org.gnome.desktop.peripherals.mouse");
        touchpad_settings = new GLib.Settings ("org.gnome.desktop.peripherals.touchpad");

        sync_gsettings_to_accountsservice ();

        mouse_settings.changed.connect ((key) => {
            if (key == "accel-profile" ||
                key == "left-handed" ||
                key == "natural-scroll" ||
                key == "speed") {
                sync_gsettings_to_accountsservice ();
            }
        });

        touchpad_settings.changed.connect ((key) => {
            if (key == "natural-scroll" ||
                key == "speed") {
                sync_gsettings_to_accountsservice ();
            }
        });
    }

    private void sync_gsettings_to_accountsservice () {
        accounts_service.accel_profile = mouse_settings.get_enum ("accel-profile");
        accounts_service.left_handed = mouse_settings.get_boolean ("left-handed");
        accounts_service.mouse_natural_scroll = mouse_settings.get_boolean ("natural-scroll");
        accounts_service.mouse_speed = mouse_settings.get_double ("speed");

        accounts_service.touchpad_natural_scroll = touchpad_settings.get_boolean ("natural-scroll");
        accounts_service.touchpad_speed = touchpad_settings.get_double ("speed");
    }
}

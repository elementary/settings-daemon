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
    private GLib.Settings interface_settings;

    public MouseSettings (AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        mouse_settings = new GLib.Settings ("org.gnome.desktop.peripherals.mouse");
        touchpad_settings = new GLib.Settings ("org.gnome.desktop.peripherals.touchpad");
        interface_settings = new GLib.Settings ("org.gnome.desktop.interface");

        if (accounts_service.left_handed != mouse_settings.get_boolean ("left-handed")) {
            mouse_settings.set_boolean ("left-handed", accounts_service.left_handed);
        }

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
            if (key == "click-method" ||
                key == "disable-while-typing" ||
                key == "edge-scrolling-enabled" ||
                key == "natural-scroll" ||
                key == "send-events" ||
                key == "speed" ||
                key == "tap-to-click" ||
                key == "two-finger-scrolling-enabled") {
                sync_gsettings_to_accountsservice ();
            }
        });

        interface_settings.changed.connect ((key) => {
            if (key == "cursor-size") {
                sync_gsettings_to_accountsservice ();
            }
        });
    }

    private void sync_gsettings_to_accountsservice () {
        accounts_service.left_handed = mouse_settings.get_boolean ("left-handed");
        accounts_service.accel_profile = mouse_settings.get_enum ("accel-profile");

        accounts_service.mouse_natural_scroll = mouse_settings.get_boolean ("natural-scroll");
        accounts_service.mouse_speed = mouse_settings.get_double ("speed");

        accounts_service.touchpad_click_method = touchpad_settings.get_enum ("click-method");
        accounts_service.touchpad_disable_while_typing = touchpad_settings.get_boolean ("disable-while-typing");
        accounts_service.touchpad_edge_scrolling = touchpad_settings.get_boolean ("edge-scrolling-enabled");
        accounts_service.touchpad_natural_scroll = touchpad_settings.get_boolean ("natural-scroll");
        accounts_service.touchpad_send_events = touchpad_settings.get_enum ("send-events");
        accounts_service.touchpad_speed = touchpad_settings.get_double ("speed");
        accounts_service.touchpad_tap_to_click = touchpad_settings.get_boolean ("tap-to-click");
        accounts_service.touchpad_two_finger_scrolling = touchpad_settings.get_boolean ("two-finger-scrolling-enabled");

        accounts_service.cursor_size = interface_settings.get_int ("cursor-size");
    }
}

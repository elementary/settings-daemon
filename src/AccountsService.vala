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
*
*/

[DBus (name = "io.elementary.SettingsDaemon.AccountsService")]
public interface SettingsDaemon.AccountsService : Object {
    /* Keyboard */
    public struct KeyboardLayout {
        public string backend;
        public string name;
    }

    public struct XkbOption {
        public string option;
    }

    public abstract KeyboardLayout[] keyboard_layouts { owned get; set; }
    public abstract uint active_keyboard_layout { get; set; }
    public abstract XkbOption[] xkb_options { owned get; set; }

    /* Mouse and Touchpad */
    public abstract bool left_handed { get; set; }
    public abstract int accel_profile { get; set; }

    public abstract bool mouse_natural_scroll { get; set; }
    public abstract double mouse_speed { get; set; }

    public abstract int touchpad_click_method { get; set; }
    public abstract bool touchpad_disable_while_typing { get; set; }
    public abstract bool touchpad_edge_scrolling { get; set; }
    public abstract bool touchpad_natural_scroll { get; set; }
    public abstract int touchpad_send_events { get; set; }
    public abstract double touchpad_speed { get; set; }
    public abstract bool touchpad_tap_to_click { get; set; }
    public abstract bool touchpad_two_finger_scrolling { get; set; }

    public abstract int cursor_size { get; set; }

    /* Night Light */
    public struct Coordinates {
        public double latitude;
        public double longitude;
    }

    public abstract bool night_light_enabled { get; set; }
    public abstract Coordinates night_light_last_coordinates { get; set; }
    public abstract bool night_light_schedule_automatic { get; set; }
    public abstract double night_light_schedule_from { get; set; }
    public abstract double night_light_schedule_to { get; set; }
    public abstract uint night_light_temperature { get; set; }
}

[DBus (name = "io.elementary.pantheon.AccountsService")]
public interface PantheonShell.Pantheon.AccountsService : Object {
    public abstract int prefers_color_scheme { get; set; }
}

[DBus (name = "org.freedesktop.Accounts")]
public interface SettingsDaemon.FDO.Accounts : Object {
    public abstract string find_user_by_name (string username) throws GLib.Error;
}

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
    public struct KeyboardLayout {
        public string backend;
        public string name;
    }

    public abstract KeyboardLayout[] keyboard_layouts { owned get; set; }
    public abstract uint active_keyboard_layout { get; set; }
    public abstract string clock_format { owned get; set; }
}

[DBus (name = "io.elementary.pantheon.AccountsService")]
public interface PantheonShell.Pantheon.AccountsService : Object {
    public abstract int prefers_color_scheme { get; set; }
}

[DBus (name = "org.freedesktop.Accounts")]
public interface SettingsDaemon.FDO.Accounts : Object {
    public abstract string find_user_by_name (string username) throws GLib.Error;
}

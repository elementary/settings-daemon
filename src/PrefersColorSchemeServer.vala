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
* Authored by: Marius Meisenzahl <mariusmeisenzahl@gmail.com>
*/

namespace SettingsDaemon {
    [DBus (name="io.elementary.SettingsDaemon.PrefersColorScheme")]
    public class PrefersColorSchemeServer : Object {
        private static GLib.Once<PrefersColorSchemeServer> instance;
        public static unowned PrefersColorSchemeServer get_default () {
            return instance.once (() => { return new PrefersColorSchemeServer (); });
        }

        private bool _active { get; set; }

        public signal void active_changed (bool value);

        public bool active {
            get {
                return _active;
            }
        }
        public bool snoozed { get; set; }

        [DBus (visible = false)]
        public void set_active (bool value) {
            _active = value;
            active_changed (value);
        }
    }
}

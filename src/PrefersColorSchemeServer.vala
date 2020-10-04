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
    [DBus (name = "io.elementary.SettingsDaemon.PrefersColorScheme")]
    public class PrefersColorSchemeServer : Object {
        public bool snoozed { get; set; }

        private weak DBusConnection connection;

        public PrefersColorSchemeServer (DBusConnection connection) {
            this.connection = connection;
            notify.connect (send_property_change);
        }

        private void send_property_change (ParamSpec p) {
            var builder = new VariantBuilder (VariantType.ARRAY);
            var invalid_builder = new VariantBuilder (new VariantType ("as"));

            if (p.name == "snoozed") {
                Variant i = snoozed;
                builder.add ("{bv}", "snoozed", i);
            }

            try {
                connection.emit_signal (null,
                                "/io/elementary/settings_daemon",
                                "org.freedesktop.DBus.Properties",
                                "PropertiesChanged",
                                new Variant ("(sa{bv}as)",
                                            "io.elementary.SettingsDaemon.PrefersColorScheme",
                                            builder,
                                            invalid_builder)
                                );
            } catch (Error e) {
                warning ("%s\n", e.message);
            }
        }
    }
}
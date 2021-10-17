/*-
 * Copyright 2021 elementary, Inc. (https://elementary.io)
 * Copyright 2021 Alexander Mikhaylenko <alexm@gnome.org>
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
 */

[DBus (name = "org.freedesktop.portal.Error")]
public errordomain PortalError {
    FAILED,
    INVALID_ARGUMENT,
    NOT_FOUND,
    EXISTS,
    NOT_ALLOWED,
    CANCELLED,
    WINDOW_DESTROYED
}

[DBus (name = "io.elementary.pantheon.AccountsService")]
private interface Pantheon.AccountsService : Object {
    public abstract int prefers_color_scheme { owned get; set; }
}

[DBus (name = "org.freedesktop.Accounts")]
interface FDO.Accounts : Object {
    public abstract string find_user_by_name (string username) throws GLib.Error;
}

/* Copied from Granite.Settings */
private class AccountsServiceMonitor : GLib.Object {
    private FDO.Accounts? accounts_service = null;
    private Pantheon.AccountsService? pantheon_act = null;
    private string user_path;

    public int32 color_scheme { get; set; }

    construct {
        setup_user_path ();
        setup_prefers_color_scheme ();
    }

    private void setup_user_path () {
        try {
            accounts_service = GLib.Bus.get_proxy_sync (
                GLib.BusType.SYSTEM,
               "org.freedesktop.Accounts",
               "/org/freedesktop/Accounts"
            );

            user_path = accounts_service.find_user_by_name (GLib.Environment.get_user_name ());
        } catch (Error e) {
            critical (e.message);
        }
    }

    private void setup_prefers_color_scheme () {
        try {
            pantheon_act = GLib.Bus.get_proxy_sync (
                GLib.BusType.SYSTEM,
                "org.freedesktop.Accounts",
                user_path,
                GLib.DBusProxyFlags.GET_INVALIDATED_PROPERTIES
            );

            color_scheme = pantheon_act.prefers_color_scheme;

            ((GLib.DBusProxy) pantheon_act).g_properties_changed.connect ((changed, invalid) => {
                var value = changed.lookup_value ("PrefersColorScheme", new VariantType ("i"));
                if (value != null) {
                    color_scheme = value.get_int32 ();
                }
            });
        } catch (Error e) {
            critical (e.message);
        }
    }
}

[DBus (name = "org.freedesktop.impl.portal.Settings")]
public class SettingsDaemon.Settings : GLib.Object {
    public uint32 version {
        get { return 1; }
    }

    public signal void setting_changed (string namespace, string key, GLib.Variant value);

    private AccountsServiceMonitor monitor;

    construct {
        monitor = new AccountsServiceMonitor ();
        monitor.notify["color-scheme"].connect (() => {
            setting_changed ("org.freedesktop.appearance", "color-scheme", get_color_scheme ());
        });
    }

    private bool namespace_matches (string namespace, string[] patterns) {
        foreach (var pattern in patterns) {
            if (pattern[0] == '\0') {
                return true;
            }

            if (pattern == namespace) {
                return true;
            }

            int pattern_len = pattern.length;
            if (pattern[pattern_len - 1] == '*' && namespace.has_prefix (pattern.slice (0, pattern_len - 1))) {
                return true;
            }
        }

        return patterns.length == 0;
    }

    private GLib.Variant get_color_scheme () {
        return new GLib.Variant.uint32 (monitor.color_scheme);
    }

    public async GLib.HashTable<string, GLib.HashTable<string, GLib.Variant>> read_all (string[] namespaces) throws GLib.DBusError, GLib.IOError {
        var ret = new GLib.HashTable<string, GLib.HashTable<string, GLib.Variant>> (str_hash, str_equal);

        if (namespace_matches ("org.freedesktop.appearance", namespaces)) {
            var dict = new HashTable<string, Variant> (str_hash, str_equal);

            dict.insert ("color-scheme", get_color_scheme ());

            ret.insert ("org.freedesktop.appearance", dict);
        }

        return ret;
    }

    public async GLib.Variant read (string namespace, string key) throws GLib.DBusError, GLib.Error {
        if (namespace == "org.freedesktop.appearance" && key == "color-scheme") {
            return get_color_scheme ();
        }

        debug ("Attempted to read unknown namespace/key pair: %s %s", namespace, key);

        throw new PortalError.NOT_FOUND ("Requested setting not found");
    }
}

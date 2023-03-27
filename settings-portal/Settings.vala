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
    public abstract int prefers_accent_color { owned get; set; }
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
    public int32 accent_color { get; set; }

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
            accent_color = pantheon_act.prefers_accent_color;

            ((GLib.DBusProxy) pantheon_act).g_properties_changed.connect ((changed, invalid) => {
                var value = changed.lookup_value ("PrefersColorScheme", new VariantType ("i"));
                if (value != null) {
                    color_scheme = value.get_int32 ();
                }

                value = changed.lookup_value ("PrefersAccentColor", new VariantType ("i"));
                if (value != null) {
                    accent_color = value.get_int32 ();
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

    private HashTable<string, GLib.Settings> settings;
    private AccountsServiceMonitor monitor;

    private const string[] SUPPORTED_SCHEMAS = {
        "io.elementary.settings-daemon.datetime",
        "org.freedesktop.appearance"
    };

    construct {
        monitor = new AccountsServiceMonitor ();
        monitor.notify["color-scheme"].connect (() => {
            setting_changed ("org.freedesktop.appearance", "color-scheme", get_color_scheme ());
        });
        monitor.notify["accent-color"].connect (() => {
            setting_changed ("org.freedesktop.appearance", "accent-color", get_accent_color ());
        });

        settings = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        foreach (var schema in SUPPORTED_SCHEMAS) {
            if (SettingsSchemaSource.get_default ().lookup (schema, true) != null) {
                settings[schema] = new GLib.Settings (schema);
                settings[schema].changed.connect ((key) => {
                    var @value = settings[schema].get_value (key);
                    setting_changed (schema, key, value);
                });
            }
        }
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

    private inline GLib.Variant rgb_to_variant (int rgb) {
        double r = ((rgb >> 16) & 255) / 255.0;
        double g = ((rgb >> 8) & 255) / 255.0;
        double b = (rgb & 255) / 255.0;

        return new GLib.Variant ("(ddd)", r, g, b);
    }

    private GLib.Variant get_accent_color () {
        switch (monitor.accent_color) {
            case 1: // Strawberry
                return rgb_to_variant (0xed5353);

            case 2: // Orange
                return rgb_to_variant (0xffa154);

            case 3: // Banana
                return rgb_to_variant (0xf9c440);

            case 4: // Lime
                return rgb_to_variant (0x68b723);

            case 5: // Mint
                return rgb_to_variant (0x28bca3);

            case 6: // Blueberry
                return rgb_to_variant (0x3689e6);

            case 7: // Grape
                return rgb_to_variant (0xa56de2);

            case 8: // Bubblegum
                return rgb_to_variant (0xde3e80);

            case 9: // Cocoa
                return rgb_to_variant (0x8a715e);

            case 10: // Slate
                return rgb_to_variant (0x667885);
        }

        return rgb_to_variant (0);
    }

    public async GLib.HashTable<string, GLib.HashTable<string, GLib.Variant>> read_all (string[] namespaces) throws GLib.DBusError, GLib.IOError {
        var ret = new GLib.HashTable<string, GLib.HashTable<string, GLib.Variant>> (str_hash, str_equal);

        foreach (var schema in SUPPORTED_SCHEMAS) {
            if (namespace_matches (schema, namespaces)) {
                var dict = new HashTable<string, Variant> (str_hash, str_equal);

                if (schema == "org.freedesktop.appearance") {
                    dict.insert ("color-scheme", get_color_scheme ());
                    dict.insert ("accent-color", get_accent_color ());
                } else {
                    var setting = settings[schema];
                    foreach (var key in setting.settings_schema.list_keys ()) {
                        dict.insert (key, setting.get_value (key));
                    }
                }

                ret.insert (schema, dict);
            }
        }

        return ret;
    }

    public async GLib.Variant read (string namespace, string key) throws GLib.DBusError, GLib.Error {
        if (namespace in SUPPORTED_SCHEMAS) {
            if (namespace == "org.freedesktop.appearance") {
                if (key == "color-scheme") {
                    return get_color_scheme ();
                }

                if (key == "accent-color") {
                    return get_accent_color ();
                }
            }

            if (settings[namespace].settings_schema.has_key (key)) {
                return settings[namespace].get_value (key);
            }
        }

        debug ("Attempted to read unknown namespace/key pair: %s %s", namespace, key);

        throw new PortalError.NOT_FOUND ("Requested setting not found");
    }
}

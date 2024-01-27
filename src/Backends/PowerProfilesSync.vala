/*
 * Copyright 2024 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class SettingsDaemon.Backends.PowerProfilesSync : GLib.Object {
    [DBus (name = "org.freedesktop.UPower")]
    private interface UPower : GLib.DBusProxy {
        public abstract bool on_battery { get; }
    }

    [DBus (name = "net.hadess.PowerProfiles")]
    private interface PowerProfile : GLib.DBusProxy {
        public abstract HashTable<string, Variant>[] profiles { owned get; }
        public abstract string active_profile { owned get; set; }
    }

    private const string PROFILE_PLUGGED_IN = "profile-plugged-in";
    private const string PROFILE_ON_BATTERY = "profile-on-battery";

    private GLib.Settings settings;
    private UPower? upower = null;
    private PowerProfile? power_profiles_daemon = null;

    construct {
        settings = new GLib.Settings("io.elementary.settings-daemon.power");

        Bus.watch_name (BusType.SYSTEM, "org.freedesktop.UPower", BusNameWatcherFlags.NONE, on_upower_watch, on_upower_unwatch);
        Bus.watch_name (BusType.SYSTEM, "net.hadess.PowerProfiles", BusNameWatcherFlags.NONE, on_ppd_watch, on_ppd_unwatch);

        settings.changed.connect (update_profile);
    }

    private void on_upower_watch (GLib.DBusConnection connection) {
        connection.get_proxy.begin<UPower> (
            "org.freedesktop.UPower", "/org/freedesktop/UPower", NONE, null,
            (obj, res) => {
                try {
                    upower = ((GLib.DBusConnection) obj).get_proxy.end<UPower> (res);
                    debug ("Connected to UPower");

                    update_profile ();

                    upower.g_properties_changed.connect ((changed_properties) => {
                        for (int i = 0; i < changed_properties.n_children (); i++) {
                            unowned string property; 
                            changed_properties.get_child (i, "{&sv}", out property, null);
                            if (property == "OnBattery") {
                                update_profile ();
                                break;
                            }
                        }
                    });
                } catch (Error e) {
                    critical (e.message);
                    upower = null;
                }
            }
        );
    }

    private void on_upower_unwatch (GLib.DBusConnection connection) {
        upower = null;
        critical ("Lost connection to UPower");
    }

    private void on_ppd_watch (GLib.DBusConnection connection) {
        connection.get_proxy.begin<PowerProfile> (
            "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", NONE, null,
            (obj, res) => {
                try {
                    power_profiles_daemon = ((GLib.DBusConnection) obj).get_proxy.end<PowerProfile> (res);
                    debug ("Connected to power profiles daemon");

                    update_profile ();
                } catch (Error e) {
                    critical (e.message);
                    power_profiles_daemon = null;
                }
            }
        );
    }

    private void on_ppd_unwatch (GLib.DBusConnection connection) {
        power_profiles_daemon = null;
        critical ("Lost connection to power profiles daemon");
    }

    private void update_profile () {
        if (power_profiles_daemon == null || upower == null) {
            return;
        }

        var profile_to_set = settings.get_string (upower.on_battery ? PROFILE_ON_BATTERY : PROFILE_PLUGGED_IN);
        
        var found_profile = false;
        var profiles = power_profiles_daemon.profiles;
        for (int i = 0; i < profiles.length; i++) {
            if (profiles[i].get ("Profile").get_string () == profile_to_set) {
                found_profile = true;
                break;
            }
        }

        if (found_profile) {
            power_profiles_daemon.active_profile = profile_to_set;
        } else {
            warning ("Couldn't set power profile to %s", profile_to_set);
        }
    }
}

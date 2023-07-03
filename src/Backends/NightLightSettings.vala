/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

 public class SettingsDaemon.Backends.NightLightSettings : GLib.Object {
    public unowned AccountsService accounts_service { get; construct; }

    private GLib.Settings night_light_settings;

    public NightLightSettings (AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        night_light_settings = new GLib.Settings ("org.gnome.settings-daemon.plugins.color");

        sync_gsettings_to_accountsservice ();

        night_light_settings.changed.connect ((key) => {
            if (key == "night-light-enabled" ||
                key == "night-light-last-coordinates" ||
                key == "night-light-schedule-automatic" ||
                key == "night-light-schedule-from" ||
                key == "night-light-schedule-to" ||
                key == "night-light-temperature") {
                sync_gsettings_to_accountsservice ();
            }
        });
    }

    private void sync_gsettings_to_accountsservice () {
        accounts_service.night_light_enabled = night_light_settings.get_boolean ("night-light-enabled");

        var last_coordinates_value = night_light_settings.get_value ("night-light-last-coordinates");
        if (last_coordinates_value.is_of_type (GLib.VariantType.TUPLE)) {
            double latitude;
            double longitude;

            last_coordinates_value.@get ("(dd)", out latitude, out longitude);

            accounts_service.night_light_last_coordinates = AccountsService.Coordinates () {
                latitude = latitude,
                longitude = longitude
            };
        } else {
            warning ("Unknown night light coordinates type, unable to save to AccountsService");
        }

        accounts_service.night_light_schedule_automatic = night_light_settings.get_boolean ("night-light-schedule-automatic");
        accounts_service.night_light_schedule_from = night_light_settings.get_double ("night-light-schedule-from");
        accounts_service.night_light_schedule_to = night_light_settings.get_double ("night-light-schedule-to");
        accounts_service.night_light_temperature = night_light_settings.get_uint ("night-light-temperature");
    }
}

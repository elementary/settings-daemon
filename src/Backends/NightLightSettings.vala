/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

 public class SettingsDaemon.Backends.NightLightSettings : GLib.Object {
    private const string NIGHT_LIGHT_SCHEMA = "org.gnome.settings-daemon.plugins.color";
    private const string NIGHT_LIGHT_ENABLED = "night-light-enabled";
    private const string NIGHT_LIGHT_LAST_COORDINATES = "night-light-last-coordinates";
    private const string NIGHT_LIGHT_SCHEDULE_AUTOMATIC = "night-light-schedule-automatic";
    private const string NIGHT_LIGHT_SCHEDULE_FROM = "night-light-schedule-from";
    private const string NIGHT_LIGHT_SCHEDULE_TO = "night-light-schedule-to";
    private const string NIGHT_LIGHT_TEMPERATURE = "night-light-temperature";

    public unowned AccountsService accounts_service { get; construct; }

    private GLib.Settings night_light_settings;

    public NightLightSettings (AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        var night_light_schema = SettingsSchemaSource.get_default ().lookup (NIGHT_LIGHT_SCHEMA, true);
        if (night_light_schema == null) {
            warning ("GSD color not found");
            return;
        }

        night_light_settings = new GLib.Settings (NIGHT_LIGHT_SCHEMA);

        sync_gsettings_to_accountsservice ();

        night_light_settings.changed.connect ((key) => {
            if (key == NIGHT_LIGHT_ENABLED ||
                key == NIGHT_LIGHT_LAST_COORDINATES ||
                key == NIGHT_LIGHT_SCHEDULE_AUTOMATIC ||
                key == NIGHT_LIGHT_SCHEDULE_FROM ||
                key == NIGHT_LIGHT_SCHEDULE_TO ||
                key == NIGHT_LIGHT_TEMPERATURE) {
                sync_gsettings_to_accountsservice ();
            }
        });
    }

    private void sync_gsettings_to_accountsservice () {
        accounts_service.night_light_enabled = night_light_settings.get_boolean (NIGHT_LIGHT_ENABLED);

        var last_coordinates_value = night_light_settings.get_value (NIGHT_LIGHT_LAST_COORDINATES);
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

        accounts_service.night_light_schedule_automatic = night_light_settings.get_boolean (NIGHT_LIGHT_SCHEDULE_AUTOMATIC);
        accounts_service.night_light_schedule_from = night_light_settings.get_double (NIGHT_LIGHT_SCHEDULE_FROM);
        accounts_service.night_light_schedule_to = night_light_settings.get_double (NIGHT_LIGHT_SCHEDULE_TO);
        accounts_service.night_light_temperature = night_light_settings.get_uint (NIGHT_LIGHT_TEMPERATURE);
    }
}

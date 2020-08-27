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

public class SettingsDaemon.Backends.PrefersColorSchemeSettings : GLib.Object {
    public unowned PantheonShell.Pantheon.AccountsService accounts_service { get; construct; }

    private GLib.Settings color_settings;
    private double pos_lat = -1.0;
    private double pos_long = -1.0;

    public PrefersColorSchemeSettings (PantheonShell.Pantheon.AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        color_settings = new GLib.Settings ("io.elementary.settings-daemon.prefers-color-scheme");

        get_location.begin ();

        var time = new TimeoutSource (1000);

        time.set_callback (() => {
            var schedule = color_settings.get_string ("prefer-dark-schedule");

            var now = new DateTime.now_local ();
            double from, to;
            if (schedule == "sunset-to-sunrise") {
                double sunrise, sunset;

                bool success = SettingsDaemon.Utils.SunriseSunsetCalculator.get_sunrise_and_sunset (now, pos_lat, pos_long, out sunrise, out sunset);

                if (success) {
                    from = sunset;
                    to = sunrise;
                }
            } else if (schedule == "manual") {
                from = color_settings.get_double ("prefer-dark-schedule-from");
                to = color_settings.get_double ("prefer-dark-schedule-to");
            } else {
                return true;
            }

            var is_in = is_in_time_window (date_time_double (now), from, to);
            var new_color_scheme = Granite.Settings.ColorScheme.NO_PREFERENCE;
            if (is_in) {
                new_color_scheme = Granite.Settings.ColorScheme.DARK;
            }

            if (new_color_scheme == accounts_service.prefers_color_scheme) {
                return true;
            }

            accounts_service.prefers_color_scheme = new_color_scheme;

            return true;
        });

        time.attach (null);
    }

    private async void get_location () {
        try {
            var simple = yield new GClue.Simple (Build.PROJECT_NAME, GClue.AccuracyLevel.CITY, null);

            simple.notify["location"].connect (() => {
                on_location_updated (simple.location.latitude, simple.location.longitude);
            });

            on_location_updated (simple.location.latitude, simple.location.longitude);
        } catch (Error e) {
            warning ("Failed to connect to GeoClue2 service: %s", e.message);
            return;
        }
    }

    private void on_location_updated (double latitude, double longitude) {
        pos_lat = latitude;
        pos_long = longitude;
    }

    public static bool is_in_time_window (double time_double, double from, double to) {
        if (from >= 0.0 && time_double >= from || time_double >= 0.0 && time_double < to) {
            return true;
        }

        return false;
    }

    public static double date_time_double (DateTime date_time) {
        double time_double = 0;
        time_double += date_time.get_hour ();
        time_double += (double) date_time.get_minute () / 60;

        return time_double;
    }
}

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
    private PrefersColorSchemeServer prefers_color_scheme_server;
    private double sunrise = -1.0;
    private double sunset = -1.0;

    private uint time_id = 0;

    public PrefersColorSchemeSettings (PantheonShell.Pantheon.AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        color_settings = new GLib.Settings ("io.elementary.settings-daemon.prefers-color-scheme");
        prefers_color_scheme_server = PrefersColorSchemeServer.get_default ();

        color_settings.changed["prefer-dark-schedule"].connect (update);
        prefers_color_scheme_server.notify.connect (update);

        var schedule = color_settings.get_string ("prefer-dark-schedule");
        if (schedule == "sunset-to-sunrise") {
            var variant = color_settings.get_value ("last-coordinates");
            on_location_updated (variant.get_child_value (0).get_double (), variant.get_child_value (1).get_double ());
        }

        update ();
    }

    private void update () {
        var schedule = color_settings.get_string ("prefer-dark-schedule");
        var snoozed = prefers_color_scheme_server.snoozed;

        if (snoozed) {
            stop_timer ();
            accounts_service.prefers_color_scheme = Granite.Settings.ColorScheme.NO_PREFERENCE;
            return;
        }

        if (schedule == "sunset-to-sunrise") {
            get_location.begin ();

            start_timer ();
        } else if (schedule == "manual") {
            start_timer ();
        } else {
            stop_timer ();
        }
    }

    private void start_timer () {
        if (time_id == 0) {
            var time = new TimeoutSource (1000);
            time.set_callback (time_callback);
            time_id = time.attach (null);
        }
    }

    private void stop_timer () {
        if (time_id != 0) {
            Source.remove (time_id);
            time_id = 0;
        }
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

    private bool time_callback () {
        var schedule = color_settings.get_string ("prefer-dark-schedule");

        var now = new DateTime.now_local ();
        double from, to;
        if (schedule == "sunset-to-sunrise") {
            if (sunrise >= 0 && sunset >= 0) {
                from = sunset;
                to = sunrise;
            } else {
                // fallback times (6AM and 8PM) for when an invalid result was returned
                // from the calculation (i.e. probably wasn't able to get a location)
                from = 20.0;
                to = 6.0;
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
    }

    private void on_location_updated (double latitude, double longitude) {
        color_settings.set_value ("last-coordinates", new Variant.tuple ({latitude, longitude}));

        var now = new DateTime.now_local ();
        double _sunrise, _sunset;
        if (SettingsDaemon.Utils.SunriseSunsetCalculator.get_sunrise_and_sunset (now, latitude, longitude, out _sunrise, out _sunset)) {
            sunrise = _sunrise;
            sunset = _sunset;
        }
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

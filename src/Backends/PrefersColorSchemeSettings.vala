/*
* Copyright 2020–2021 elementary, Inc. (https://elementary.io)
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

public class SettingsDaemon.Backends.PrefersColorSchemeSettings : Object {
    public unowned Pantheon.AccountsService accounts_service { get; construct; }

    private const string COLOR_SCHEME = "color-scheme";
    private const string DARK_SCHEDULE = "prefer-dark-schedule";
    private const string DARK_SCHEDULE_SNOOZED = "prefer-dark-schedule-snoozed";

    private Settings color_settings;
    private double sunrise = -1.0;
    private double sunset = -1.0;

    private uint time_id = 0;

    public PrefersColorSchemeSettings (Pantheon.AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        color_settings = new Settings ("io.elementary.settings-daemon.prefers-color-scheme");

        var schedule = color_settings.get_string (DARK_SCHEDULE);
        if (schedule == "sunset-to-sunrise") {
            var variant = color_settings.get_value ("last-coordinates");
            on_location_updated (variant.get_child_value (0).get_double (), variant.get_child_value (1).get_double ());
        }

        color_settings.changed[DARK_SCHEDULE].connect (update_timer);
        color_settings.changed[COLOR_SCHEME].connect (update_color_scheme);

        update_timer ();
    }

    private void update_timer () {
        var schedule = color_settings.get_string (DARK_SCHEDULE);

        if (schedule == "sunset-to-sunrise") {
            get_location.begin ();

            start_timer ();
        } else if (schedule == "manual") {
            start_timer ();
        } else {
            color_settings.set_boolean (DARK_SCHEDULE_SNOOZED, false);
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
        var new_color_scheme = Granite.Settings.ColorScheme.NO_PREFERENCE;
        if (is_in_schedule ()) {
            new_color_scheme = Granite.Settings.ColorScheme.DARK;
        }

        if (new_color_scheme == color_settings.get_enum (COLOR_SCHEME)) {
            color_settings.set_boolean (DARK_SCHEDULE_SNOOZED, false);
            return true;
        }

        if (!color_settings.get_boolean (DARK_SCHEDULE_SNOOZED)) {
            color_settings.set_enum (COLOR_SCHEME, new_color_scheme);
            return true;
        };

        return GLib.Source.CONTINUE;
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

    private void update_color_scheme () {
        var color_scheme = color_settings.get_enum (COLOR_SCHEME);
        if (
            color_scheme == Granite.Settings.ColorScheme.DARK && !is_in_schedule () ||
            color_scheme != Granite.Settings.ColorScheme.DARK && is_in_schedule ()
        ) {
            color_settings.set_boolean (DARK_SCHEDULE_SNOOZED, true);
        }

        accounts_service.prefers_color_scheme = color_scheme;

        var mutter_settings = new GLib.Settings ("org.gnome.desktop.interface");
        mutter_settings.set_enum ("color-scheme", color_scheme);
    }

    private bool is_in_schedule () {
        var schedule = color_settings.get_string (DARK_SCHEDULE);

        // fallback times (6AM and 8PM) for when an invalid result was returned
        // from the calculation (i.e. probably wasn't able to get a location)
        double from = 20.0;
        double to = 6.0;
        if (schedule == "sunset-to-sunrise" && sunrise >= 0 && sunset >= 0) {
            from = sunset;
            to = sunrise;
        } else if (schedule == "manual") {
            from = color_settings.get_double ("prefer-dark-schedule-from");
            to = color_settings.get_double ("prefer-dark-schedule-to");
        }

        var now = new DateTime.now_local ();
        return is_in_time_window (date_time_double (now), from, to);
    }

    public static bool is_in_time_window (double time_double, double from, double to) {
        // PM to AM
        if (from > to) {
            return time_double < to ? time_double <= from : time_double >= from;
        }

        // AM to AM, PM to PM, AM to PM
        return (time_double >= from && time_double <= to);
    }

    public static double date_time_double (DateTime date_time) {
        double time_double = 0;
        time_double += date_time.get_hour ();
        time_double += (double) date_time.get_minute () / 60;

        return time_double;
    }
}

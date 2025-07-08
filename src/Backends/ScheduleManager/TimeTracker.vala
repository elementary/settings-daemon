/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

[SingleInstance]
public class SettingsDaemon.Backends.TimeTracker : Object {
    private GClue.Simple simple;

    private double sunrise = 6.0;
    private double sunset = 20.0;

    construct {
        get_location.begin ();
    }

    private async void get_location () {
        try {
            simple = yield new GClue.Simple (Build.PROJECT_NAME, GClue.AccuracyLevel.CITY, null);

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
        var now = new DateTime.now_local ();
        double _sunrise, _sunset;
        if (SettingsDaemon.Utils.SunriseSunsetCalculator.get_sunrise_and_sunset (now, latitude, longitude, out _sunrise, out _sunset)) {
            sunrise = _sunrise;
            sunset = _sunset;
        }
    }

    public bool is_in_time_window_daylight () {
        var date_time = new DateTime.now_local ();
        double time_double = 0;
        time_double += date_time.get_hour ();
        time_double += (double) date_time.get_minute () / 60;

        // PM to AM
        if (sunset > sunrise) {
            return time_double < sunrise ? time_double <= sunset : time_double >= sunset;
        }

        // AM to AM, PM to PM, AM to PM
        return (time_double >= sunset && time_double <= sunrise);
    }

    public bool is_in_time_window_manual (double from, double to) {
        var date_time = new DateTime.now_local ();
        double time_double = 0;
        time_double += date_time.get_hour ();
        time_double += (double) date_time.get_minute () / 60;

        // PM to AM
        if (from > to) {
            return time_double < to ? time_double <= from : time_double >= from;
        }

        // AM to AM, PM to PM, AM to PM
        return (time_double >= from && time_double <= to);
    }
}

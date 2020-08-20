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

    public PrefersColorSchemeSettings (PantheonShell.Pantheon.AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        color_settings = new GLib.Settings ("io.elementary.settings-daemon.prefers-color-scheme");

        var time = new TimeoutSource (1000);

        time.set_callback (() => {
            var schedule = color_settings.get_string ("prefer-dark-schedule");

            double from, to;
            if (schedule == "sunset-to-sunrise") {
                from = 20.0;
                to = 6.0;
            } else if (schedule == "manual") {
                from = color_settings.get_double ("prefer-dark-schedule-from");
                to = color_settings.get_double ("prefer-dark-schedule-to");
            } else {
                return true;
            }

            var now = new DateTime.now_local ();

            var state = get_state (date_time_double (now), from, to);
            var new_color_scheme = Granite.Settings.ColorScheme.NO_PREFERENCE;
            if (state == State.IN) {
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

    private enum State {
        UNKNOWN,
        IN,
        OUT
    }

    private State get_state (double time_double, double from, double to) {
        if (from >= 0.0 && time_double >= from || time_double >= 0.0 && time_double < to) {
            return State.IN;
        }

        return State.OUT;
    }

    private double date_time_double (DateTime date_time) {
        double time_double = 0;
        time_double += date_time.get_hour ();
        time_double += (double) date_time.get_minute () / 60;

        return time_double;
    }
}

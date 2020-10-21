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

/*
* The following code was ported from gnome-settings-daemon
* https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/blob/02295dee94bebcdd246c40ccf0120eb2ab714416/plugins/color/gsd-night-light-common.c
*/

public class SettingsDaemon.Utils.SunriseSunsetCalculator {
    public static bool get_sunrise_and_sunset (DateTime dt, double pos_lat, double pos_long, out double sunrise, out double sunset) {
        sunrise = -1.0;
        sunset = -1.0;

        var dt_zero = new DateTime.utc (1900, 1, 1, 0, 0, 0);
        var ts = dt.difference (dt_zero);

        const int _G_USEC_PER_SEC = 1000000;

        if (!(pos_lat <= 90.0f && pos_lat >= -90.0f)) {
            return false;
        }

        if (!(pos_long <= 180.0f && pos_long >= -180.0f)) {
            return false;
        }

        double tz_offset = (double) dt.get_utc_offset () / _G_USEC_PER_SEC / 60 / 60; // B5
        double date_as_number = ts / _G_USEC_PER_SEC / 24 / 60 / 60 + 2;  // B7
        double time_past_local_midnight = 0;  // E2, unused in this calculation
        double julian_day = date_as_number + 2415018.5 +
                            time_past_local_midnight - tz_offset / 24;
        double julian_century = (julian_day - 2451545) / 36525;
        double geom_mean_long_sun = Math.fmod (280.46646 + julian_century *
                            (36000.76983 + julian_century * 0.0003032), 360);
        double geom_mean_anom_sun = 357.52911 + julian_century *
                            (35999.05029 - 0.0001537 * julian_century);  // J2
        double eccent_earth_orbit = 0.016708634 - julian_century *
                            (0.000042037 + 0.0000001267 * julian_century); // K2
        double sun_eq_of_ctr = Math.sin (deg2rad (geom_mean_anom_sun)) *
                            (1.914602 - julian_century * (0.004817 + 0.000014 * julian_century)) +
                            Math.sin (deg2rad (2 * geom_mean_anom_sun)) * (0.019993 - 0.000101 * julian_century) +
                            Math.sin (deg2rad (3 * geom_mean_anom_sun)) * 0.000289; // L2
        double sun_true_long = geom_mean_long_sun + sun_eq_of_ctr; // M2
        double sun_app_long = sun_true_long - 0.00569 - 0.00478 *
                            Math.sin (deg2rad (125.04 - 1934.136 * julian_century)); // P2
        double mean_obliq_ecliptic = 23 + (26 + ((21.448 - julian_century *
                            (46.815 + julian_century * (0.00059 - julian_century * 0.001813)))) / 60) / 60; // Q2
        double obliq_corr = mean_obliq_ecliptic + 0.00256 *
                            Math.cos (deg2rad (125.04 - 1934.136 * julian_century)); // R2
        double sun_declin = rad2deg (Math.asin (Math.sin (deg2rad (obliq_corr)) *
                                                Math.sin (deg2rad (sun_app_long)))); // T2
        double var_y = Math.tan (deg2rad (obliq_corr / 2)) * Math.tan (deg2rad (obliq_corr / 2)); // U2
        double eq_of_time = 4 * rad2deg (var_y * Math.sin (2 * deg2rad (geom_mean_long_sun)) -
                            2 * eccent_earth_orbit * Math.sin (deg2rad (geom_mean_anom_sun)) +
                            4 * eccent_earth_orbit * var_y *
                                    Math.sin (deg2rad (geom_mean_anom_sun)) *
                                    Math.cos (2 * deg2rad (geom_mean_long_sun)) -
                            0.5 * var_y * var_y * Math.sin (4 * deg2rad (geom_mean_long_sun)) -
                            1.25 * eccent_earth_orbit * eccent_earth_orbit *
                                    Math.sin (2 * deg2rad (geom_mean_anom_sun))); // V2
        double ha_sunrise = rad2deg (Math.acos (Math.cos (deg2rad (90.833)) / (Math.cos (deg2rad (pos_lat)) *
                            Math.cos (deg2rad (sun_declin))) - Math.tan (deg2rad (pos_lat)) *
                            Math.tan (deg2rad (sun_declin)))); // W2
        double solar_noon = (720 - 4 * pos_long - eq_of_time + tz_offset * 60) / 1440; // X2
        double sunrise_time = solar_noon - ha_sunrise * 4 / 1440; //  Y2
        double sunset_time = solar_noon + ha_sunrise * 4 / 1440; // Z2

        sunrise = sunrise_time * 24;
        sunset = sunset_time * 24;

        return true;
    }

    private static double deg2rad (double degrees) {
        return (Math.PI * degrees) / 180.0f;
    }

    private static double rad2deg (double radians) {
        return radians * (180.0f / Math.PI);
    }
}

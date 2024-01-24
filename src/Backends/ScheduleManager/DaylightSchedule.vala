public class SettingsDaemon.Backends.DaylightSchedule : Schedule {
    private double sunrise = 6.0;
    private double sunset = 20.0;

    public DaylightSchedule.from_parsed (Parsed parsed) {
        base.from_parsed (parsed);
    }

    construct {
        get_location.begin ();
        Timeout.add (1000, time_callback);
    }

    private bool time_callback () {
        var is_in = is_in_time_window ();

        if (active != is_in) {
            active = is_in;
        }

        return Source.CONTINUE;
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
        var now = new DateTime.now_local ();
        double _sunrise, _sunset;
        if (SettingsDaemon.Utils.SunriseSunsetCalculator.get_sunrise_and_sunset (now, latitude, longitude, out _sunrise, out _sunset)) {
            sunrise = _sunrise;
            sunset = _sunset;
        }
    }

    private bool is_in_time_window () {
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
}
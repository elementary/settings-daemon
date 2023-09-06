public class SettingsDaemon.Backends.WeatherAlerts : Object {
    private const string API_KEY = "9d9c2fa1c0024a4b9fc152215232108";

    private double latitude;
    private double longitude;

    construct {
        init_location.begin (() => {
            update_alerts.begin ();
        });

        Timeout.add_seconds (3600, () => {
            update_alerts.begin ();
            return Source.CONTINUE;
        });
    }

    private async void init_location () {
        try {
            var simple = yield new GClue.Simple (Build.PROJECT_NAME, GClue.AccuracyLevel.CITY, null);

            simple.notify["location"].connect (() => {
                latitude = simple.location.latitude;
                longitude = simple.location.longitude;
                update_alerts.begin ();
            });

            latitude = simple.location.latitude;
            longitude = simple.location.longitude;
        } catch (Error e) {
            warning ("Failed to connect to GeoClue2 service: %s", e.message);
            return;
        }
    }

    private async void update_alerts () {
        var session = new Soup.Session ();

        var msg = new Soup.Message (
            "GET",
            "http://api.weatherapi.com/v1/forecast.json?key=%s&q=%s,%s&days=1&aqi=no&alerts=yes".printf (
                API_KEY,
                latitude.to_string (),
                longitude.to_string ()
            )
        );

        msg.finished.connect (() => {
            if (msg.status_code != Soup.Status.OK) {
                warning ("Failed with status code %u (%s)", msg.status_code, Soup.Status.get_phrase (msg.status_code));
            }
        });

        try {
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            var json_parser = new Json.Parser ();
            try {
                string data = (string) bytes.get_data ();
                json_parser.load_from_data (data);
                var node = json_parser.get_root ();
                if (node == null) {
                    warning ("No JSON root node found!");
                    return;
                }

                unowned var obj = node.get_object ();
                if (obj == null) {
                    warning ("No root object found!");
                    return;
                }

                unowned var location_obj = obj.get_object_member ("location");
                if (location_obj != null) {
                    debug (
                        "Getting alerts for %s, %s, %s",
                        location_obj.get_string_member ("name"),
                        location_obj.get_string_member ("region"),
                        location_obj.get_string_member ("country")
                    );
                }

                unowned var alerts = obj.get_object_member ("alerts");
                if (alerts == null) {
                    warning ("No alerts object found!");
                    return;
                }

                unowned var array = alerts.get_array_member ("alert");
                if (array == null) {
                    warning ("No alerts array found!");
                    return;
                }

                unowned var app = GLib.Application.get_default ();
                array.foreach_element ((array, index, element_node) => {
                    unowned var alert_obj = element_node.get_object ();
                    if (alert_obj == null) {
                        warning ("No alert object found!");
                        return;
                    }

                    var start_time = new DateTime.from_iso8601 (alert_obj.get_string_member ("effective"), null);

                    var notification = new Notification (
                        "%s starting %s on %s".printf (
                            alert_obj.get_string_member ("event"),
                            start_time.format (Granite.DateTime.get_default_time_format ()),
                            start_time.format (Granite.DateTime.get_default_date_format ())
                        )
                    );
                    notification.set_icon (new ThemedIcon ("dialog-error"));
                    notification.set_body (alert_obj.get_string_member ("headline"));

                    app.send_notification (alert_obj.get_string_member ("headline"), notification);
                });
            } catch (Error e) {
                warning ("Failed to parse response as json: %s", e.message);
            }
        } catch (Error e) {
            critical ("Failed to send soup message: %s", e.message);
        }
    }
}

public class SettingsDaemon.Backends.Schedule : Object {
    public enum Type {
        MANUAL,
        DAYLIGHT
    }

    public struct Parsed {
        string id;
        Type type;
        string name;
        bool enabled;
        HashTable<string, Variant> args;
        HashTable<string, Variant> active_settings;
        HashTable<string, Variant> inactive_settings;
    }

    public Parsed parsed { get; construct set; }

    public string id { get { return parsed.id; } }
    public Type schedule_type { get { return parsed.type; } }
    public string name { get { return parsed.name; } }
    public bool enabled { get { return parsed.enabled; } }
    public HashTable<string, Variant> args { get { return parsed.args; } }
    public HashTable<string, Variant> active_settings { get { return parsed.active_settings; } }
    public HashTable<string, Variant> inactive_settings { get { return parsed.inactive_settings; } } //Inactive settings should usually be !active_settings but can also be e.g. a default wallpaper path

    public bool active { get; protected set; default = false; }

    private TimeTracker time_tracker;

    public Schedule (Parsed parsed) {
        Object (parsed: parsed);
    }

    construct {
        time_tracker = new TimeTracker ();
        Timeout.add (1000, time_callback);
    }

    /* Convenience method to add the same boolean inverted to inactive settings */
    public void add_boolean (string key, bool val) {
        active_settings[key] = val;
        inactive_settings[key] = !val;
    }

    private bool time_callback () {
        bool is_in = false;
        switch (schedule_type) {
            case MANUAL:
                if ("from" in args && "to" in args) {
                    is_in = time_tracker.is_in_time_window_manual (args["from"].get_double (), args["to"].get_double ());
                }
                break;

            case DAYLIGHT:
                is_in = time_tracker.is_in_time_window_daylight ();
                break;
        }

        if (active != is_in) {
            active = is_in;
        }

        return Source.CONTINUE;
    }
}

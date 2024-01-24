public class SettingsDaemon.Backends.Schedule : Object {
    public enum Type {
        MANUAL,
        DAYLIGHT
    }

    public struct Parsed {
        Type type;
        HashTable<string, Variant> args;
        HashTable<string, Variant> active_settings;
        HashTable<string, Variant> inactive_settings;
    }

    public bool active { get; protected set; default = false; }
    public HashTable<string, Variant> active_settings { get; private set; }
    public HashTable<string, Variant> inactive_settings { get; private set; } //Inactive settings should usually be !active_settings but can also be e.g. a default wallpaper path

    public Schedule () {
        active_settings = new HashTable<string, Variant> (str_hash, str_equal);
        inactive_settings = new HashTable<string, Variant> (str_hash, str_equal);
    }

    public Schedule.from_parsed (Parsed parsed) {
        active_settings = parsed.active_settings;
        inactive_settings = parsed.inactive_settings;
    }

    /* Convenience method to add the same boolean inverted to inactive settings */
    public void add_boolean (string key, bool val) {
        active_settings[key] = val;
        inactive_settings[key] = !val;
    }

    public Parsed get_parsed () {
        Parsed result = {
            0,
            get_private_args (),
            active_settings,
            inactive_settings
        };
        return result;
    }

    protected virtual HashTable<string, Variant> get_private_args () {
        return new HashTable<string, Variant> (str_hash, str_equal);
    }
}

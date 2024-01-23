public class SettingsDaemon.Backends.Schedule : Object {
    public bool active { get; protected set; default = false; }
    public HashTable<string, Variant> active_settings { get; private set; }
    public HashTable<string, Variant> inactive_settings { get; private set; } //Inactive settings should usually be !active_settings but can also be a default wallpaper path

    construct {
        active_settings = new HashTable<string, Variant> (str_hash, str_equal);
        inactive_settings = new HashTable<string, Variant> (str_hash, str_equal);
    }

    public void add_boolean (string key, bool val) {
        active_settings[key] = val;
        inactive_settings[key] = !val;
    }
}
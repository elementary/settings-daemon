[DBus (name="org.pantheon.gala.DesktopIntegration")]
public interface DesktopIntegration : GLib.Object {
    public struct RunningApplication {
        string app_id;
        GLib.HashTable<unowned string, Variant> details;
    }

    public struct Window {
        uint64 uid;
        GLib.HashTable<unowned string, Variant> properties;
    }

    public abstract RunningApplication[] get_running_applications () throws GLib.DBusError, GLib.IOError;
    public abstract Window[] get_windows () throws GLib.DBusError, GLib.IOError;
    public abstract void focus_window (uint64 uid) throws GLib.DBusError, GLib.IOError;
}

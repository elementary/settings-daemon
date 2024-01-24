[DBus (name="io.elementary.settings_daemon.ScheduleManager")]
public class SettingsDaemon.Backends.ScheduleManager : GLib.Object {
    private const string NIGHT_LIGHT = "night-light";
    private const string DARK_MODE = "dark-mode";
    private const string DND = "dnd";

    private static Settings settings = new Settings ("io.elementary.settings-daemon.schedules");
    private static Settings dnd_settings = new Settings ("io.elementary.notifications");

    [DBus (visible=false)]
    public unowned Pantheon.AccountsService? pantheon_service { get; set; }

    private HashTable<string, Schedule> schedules = new HashTable<string, Schedule> (str_hash, str_equal);

    construct {
        foreach (var parsed_schedule in (Schedule.Parsed[]) settings.get_value ("schedules")) {
            create_schedule_internal (parsed_schedule);
        }
    }

    public void create_schedule (Schedule.Parsed parsed) throws DBusError, IOError {
        if (parsed.name in schedules) {
            throw new IOError.EXISTS ("Schedule with the same name already exists");
        }

        create_schedule_internal (parsed);

        save_schedules ();
    }

    private void create_schedule_internal (Schedule.Parsed parsed) {
        if (parsed.name in schedules) {
            warning ("Schedule with the same name already exists");
            return;
        }

        switch (parsed.type) {
            case MANUAL:
                add_schedule (new ManualSchedule.from_parsed (parsed));
                break;
            case DAYLIGHT:
                add_schedule (new DaylightSchedule.from_parsed (parsed));
                break;
            default:
                break;
        }
    }

    public Schedule.Parsed[] list_schedules () throws DBusError, IOError {
        Schedule.Parsed[] parsed_schedules = {};
        foreach (var schedule in schedules.get_values ()) {
            parsed_schedules += schedule.get_parsed ();
        }

        return parsed_schedules;
    }

    public void update_schedule (Schedule.Parsed parsed) throws DBusError, IOError {
        if (!(parsed.name in schedules)) {
            throw new IOError.NOT_FOUND ("Schedule with the same name not found");
        }

        var schedule = schedules[parsed.name];

        if (schedule.schedule_type != parsed.type) {
            schedules.remove (schedule.name);
            create_schedule_internal (parsed);
            return;
        }

        schedule.update (parsed);

        save_schedules ();
    }

    public void delete_schedule (string name) throws DBusError, IOError {
        if (!(name in schedules)) {
            throw new IOError.NOT_FOUND ("Schedule with the same name not found");
        }

        schedules.remove (name);

        save_schedules ();
    }

    private void add_schedule (Schedule schedule) {
        schedule.notify["active"].connect (() => schedule_active_changed (schedule));
        schedule_active_changed (schedule);

        schedules[schedule.name] = schedule;
    }

    private void schedule_active_changed (Schedule schedule) {
        if (schedule.enabled) {
            activate_settings (schedule.active ? schedule.active_settings : schedule.inactive_settings);
        }
    }

    private void activate_settings (HashTable<string, Variant> settings) {
        foreach (var key in settings.get_keys ()) {
            switch (key) {
                case NIGHT_LIGHT:
                    //TODO
                    break;
                case DARK_MODE:
                    if (pantheon_service != null) {
                        pantheon_service.prefers_color_scheme = ((bool) settings[DARK_MODE]) ? Granite.Settings.ColorScheme.DARK : Granite.Settings.ColorScheme.LIGHT;
                    }
                    break;
                case DND:
                    dnd_settings.set_boolean ("do-not-disturb", (bool) settings[DND]);
                    break;
                default:
                    break;
            }
        }
    }

    private void save_schedules () {
        Schedule.Parsed[] parsed_schedules = {};
        foreach (var schedule in schedules.get_values ()) {
            parsed_schedules += schedule.get_parsed ();
        }

        settings.set_value ("schedules", parsed_schedules);
    }
}

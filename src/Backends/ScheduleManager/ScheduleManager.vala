public class SettingsDaemon.Backends.ScheduleManager : GLib.Object {
    private const string NIGHT_LIGHT = "night-light";
    private const string DARK_MODE = "dark-mode";

    private static Settings settings = new Settings ("io.elementary.settings-daemon.schedules");

    public unowned Pantheon.AccountsService pantheon_service { get; construct; }

    private List<Schedule> schedules = new List<Schedule> ();

    public ScheduleManager (Pantheon.AccountsService pantheon_service ) {
        Object (pantheon_service: pantheon_service);
    }

    construct {
        foreach (var parsed_schedule in (Schedule.Parsed[]) settings.get_value ("schedules")) {
            switch (parsed_schedule.type) {
                case MANUAL:
                    add_schedule (new ManualSchedule.from_parsed (parsed_schedule));
                    break;
                case DAYLIGHT:
                    add_schedule (new DaylightSchedule.from_parsed (parsed_schedule));
                    break;
                default:
                    break;
            }
        }
    }

    private void add_schedule (Schedule schedule) {
        schedule.notify["active"].connect (() => {
            activate_settings (schedule.active ? schedule.active_settings : schedule.inactive_settings);
        });
        activate_settings (schedule.active ? schedule.active_settings : schedule.inactive_settings);

        schedules.append (schedule);
    }

    public void activate_settings (HashTable<string, Variant> settings) {
        foreach (var key in settings.get_keys ()) {
            switch (key) {
                case NIGHT_LIGHT:
                    //TODO
                    break;
                case DARK_MODE:
                    pantheon_service.prefers_color_scheme = ((bool) settings[DARK_MODE]) ? Granite.Settings.ColorScheme.DARK : Granite.Settings.ColorScheme.LIGHT;
                    break;
                default:
                    break;
            }
        }
    }
}

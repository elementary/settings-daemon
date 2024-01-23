public class SettingsDaemon.Backends.ScheduleManager : GLib.Object {
    private const string NIGHT_LIGHT = "night-light";
    private const string DARK_MODE = "dark-mode";

    public unowned Pantheon.AccountsService pantheon_service { get; construct; }

    private List<Schedule> schedules = new List<Schedule> ();

    public ScheduleManager (Pantheon.AccountsService pantheon_service ) {
        Object (pantheon_service: pantheon_service);
    }

    construct {
        var schedule = new ManualSchedule (0.2, 10);
        schedule.add_boolean (DARK_MODE, true);

        add_schedule (schedule);
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
                    if (((bool?) settings[NIGHT_LIGHT]) != null) {
                        //  accounts_service.night_light_enabled = (bool) settings[NIGHT_LIGHT];
                    }
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
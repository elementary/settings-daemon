[DBus (name="io.elementary.settings_daemon.SystemUpdate")]
public class SettingsDaemon.Backends.SystemUpdate : Object {
    public enum State {
        UP_TO_DATE,
        CHECKING,
        AVAILABLE,
        DOWNLOADING,
        RESTART_REQUIRED
    }

    public struct CurrentState {
        State state;
        int progress;
    }

    public struct UpdateDetails {
        string[] packages;
        int size;
    }

    public signal void state_changed ();

    public CurrentState current_state { get; private set; }
    public UpdateDetails update_details { get; private set; default = UpdateDetails (); }

    private Pk.Task task;
    private Pk.PackageSack? available_updates = null;

    construct {
        current_state = {
            UP_TO_DATE,
            0
        };

        task = new Pk.Task () {
            only_download = true
        };
        check_for_updates.begin ();
    }

    private async void check_for_updates (bool force = false) {
        if (current_state.state != UP_TO_DATE && !force) {
            return;
        }

        update_state (CHECKING);

        try {
            available_updates = (yield task.get_updates_async (Pk.Filter.NONE, null, () => {})).get_package_sack ();

            if (available_updates == null || available_updates.get_size () == 0) {
                update_state (UP_TO_DATE);
                return;
            }

            string[] package_names = {};

            foreach (var package in available_updates.get_array ()) {
                package_names += package.get_name ();
            }

            update_details = {
                package_names,
                0
            };

            update_state (AVAILABLE);
        } catch (Error e) {
            warning ("Failed to get available updates: %s", e.message);
            update_state (UP_TO_DATE);
        }
    }

    public async void update () throws DBusError, IOError {
        if (current_state.state != AVAILABLE) {
            return;
        }

        update_state (DOWNLOADING, 0);

        try {
            var result = yield task.update_packages_async (available_updates.get_ids (), null, (progress, progress_type) => {
                if (progress_type == PERCENTAGE) {
                    update_state (DOWNLOADING, progress.percentage);
                }
            });

            Pk.offline_trigger (REBOOT);

            update_state (RESTART_REQUIRED, 0);
        } catch (Error e) {
            warning ("Failed to get available updates: %s", e.message);

            //This will also flush any already downloaded updates and disable the offline trigger
            check_for_updates.begin (true);
        }
    }

    private void update_state (State state, int progress = 0) {
        current_state = {
            state,
            progress
        };

        state_changed ();
    }
}
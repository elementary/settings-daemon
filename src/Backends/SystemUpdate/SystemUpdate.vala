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
    private Error? last_error = null;

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
            yield task.refresh_cache_async (false, null, () => {});
        } catch (Error e) {
            warning ("Failed to refresh cache: %s", e.message);
        }

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

            string title = ngettext ("Update Available", "Updates Available", available_updates.get_size ());
            string body = ngettext ("%u update is available for your system", "%u updates are available for your system", available_updates.get_size ()).printf (available_updates.get_size ());

            var notification = new Notification (title);
            notification.set_body (body);
            notification.set_icon (new ThemedIcon ("software-update-available"));
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

            GLib.Application.get_default ().send_notification (null, notification);

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
            critical ("Failed to download available updates: %s", e.message);

            string title = _("Update failed");
            string body = _("An Error occured while trying to update your system");

            var notification = new Notification (title);
            notification.set_body (body);
            notification.set_icon (new ThemedIcon ("dialog-error"));
            notification.add_button (_("Show details"), Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

            GLib.Application.get_default ().send_notification (null, notification);

            last_error = e;

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
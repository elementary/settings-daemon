/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

[DBus (name="io.elementary.settings_daemon.SystemUpdate")]
public class SettingsDaemon.Backends.SystemUpdate : Object {
    public struct UpdateDetails {
        string[] packages;
        int size;
        Pk.Info[] info;
    }

    private const string NOTIFICATION_ID = "system-update";

    public signal void state_changed ();

    private static Settings settings = new GLib.Settings ("io.elementary.settings-daemon.system-update");

    private PkUtils.CurrentState current_state;
    private UpdateDetails update_details;

    private Pk.Task task;
    private Pk.PackageSack? available_updates = null;
    private GLib.Cancellable cancellable;

    construct {
        current_state = {
            UP_TO_DATE,
            "",
            0,
            0
        };

        update_details = {
            {},
            0,
            {}
        };

        task = new Pk.Task () {
            only_download = true
        };

        cancellable = new GLib.Cancellable ();

        try {
            var last_offline_results = Pk.offline_get_results ();

            if (last_offline_results.get_exit_code () != SUCCESS && last_offline_results.get_error_code () != null) {
                send_error (last_offline_results.get_error_code ().details);
            } else {
                GLib.Application.get_default ().withdraw_notification (NOTIFICATION_ID);
            }
        } catch (Error e) {
            warning ("Couldn't determine last offline results: %s", e.message);
        }

        check_for_updates.begin (false, true);

        Timeout.add_seconds ((uint) settings.get_int64 ("refresh-interval"), () => {
            check_for_updates.begin (false, true);
            return Source.CONTINUE;
        });
    }

    public async void check_for_updates (bool force, bool notify) throws DBusError, IOError {
        if (SettingsDaemon.Utils.is_running_in_demo_mode () && !force) {
            return;
        }

        if (current_state.state != UP_TO_DATE && current_state.state != AVAILABLE && !force) {
            return;
        }

        update_state (CHECKING);

        try {
            var prepared = Pk.offline_get_prepared_ids ().length > 0;

            if (prepared) {
                update_state (RESTART_REQUIRED);
                return;
            }
        } catch (Error e) {
            warning ("Failed to get offline prepared ids: %s", e.message);
        }

        try {
            yield task.refresh_cache_async (force, null, progress_callback);
        } catch (Error e) {
            warning ("Failed to refresh cache: %s", e.message);
        }

        try {
            available_updates = (yield task.get_updates_async (Pk.Filter.NONE, null, progress_callback)).get_package_sack ();

            settings.set_int64 ("last-refresh-time", new DateTime.now_utc ().to_unix ());

            if (available_updates == null || available_updates.get_size () == 0) {
                update_state (UP_TO_DATE);
                return;
            }

            string[] package_names = {};
            Pk.Info[] package_info = {};
            bool security_updates = false;

            foreach (var package in available_updates.get_array ()) {
                package_names += package.get_name ();
                package_info += package.get_info ();

                if (package.get_info () == SECURITY) {
                    security_updates = true;
                }
            }

            update_details = {
                package_names,
                0, //FIXME: Is there a way to get update size from PackageKit
                package_info
            };

            update_state (AVAILABLE);

            var metered_network = NetworkMonitor.get_default ().network_metered;
            var auto_updates = settings.get_boolean ("automatic-updates");

            if (!force && !metered_network && auto_updates) {
                update.begin ();
                return;
            }

            if (notify || (metered_network && auto_updates)) {
                var notification = new Notification (_("Update available"));
                notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

                if (security_updates) {
                    notification.set_body (_("A system security update is available"));
                    notification.set_icon (new ThemedIcon ("software-update-urgent"));
                    notification.set_priority (HIGH);
                } else {
                    notification.set_body (_("A system update is available"));
                    notification.set_icon (new ThemedIcon ("software-update-available"));
                }

                GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);
            }
        } catch (Error e) {
            warning ("Failed to get available updates: %s", e.message);
            update_state (UP_TO_DATE);
        }
    }

    public async void update () throws DBusError, IOError {
        if (current_state.state != AVAILABLE) {
            return;
        }

        cancellable.reset ();

        update_state (DOWNLOADING);

        try {
            var results = yield task.update_packages_async (available_updates.get_ids (), cancellable, progress_callback);

            if (results.get_exit_code () == CANCELLED) {
                debug ("Updates were cancelled");
                check_for_updates.begin (true, false);
                return;
            }

            var notification = new Notification (_("Restart required"));
            notification.set_body (_("Please restart your system to finalize updates"));
            notification.set_icon (new ThemedIcon ("system-reboot"));
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

            GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);

            update_state (RESTART_REQUIRED);
        } catch (Error e) {
            critical ("Failed to download available updates: %s", e.message);
            send_error (e.message);
        }
    }

    public void cancel () throws DBusError, IOError {
        cancellable.cancel ();
    }

    private void progress_callback (Pk.Progress progress, Pk.ProgressType progress_type) {
        update_state (current_state.state, PkUtils.status_to_title (progress.status),
            progress.percentage, progress.download_size_remaining);
    }

    private void send_error (string message) {
        var notification = new Notification (_("System updates couldn't be installed"));
        notification.set_body (_("An error occurred while trying to update your system"));
        notification.set_icon (new ThemedIcon ("dialog-error"));
        notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

        GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);

        update_state (ERROR, message);
    }

    private void update_state (PkUtils.State state, string message = "",
        uint percentage = 0, uint64 download_size_remaining = 0) {
        current_state = {
            state,
            message,
            percentage,
            download_size_remaining
        };

        state_changed ();
    }

    public async PkUtils.CurrentState get_current_state () throws DBusError, IOError {
        return current_state;
    }

    public async UpdateDetails get_update_details () throws DBusError, IOError {
        return update_details;
    }
}

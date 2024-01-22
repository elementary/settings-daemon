/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

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
        string status;
    }

    public struct UpdateDetails {
        string[] packages;
        int size;
    }

    public signal void state_changed ();

    private static Settings settings;

    static construct {
        settings = new GLib.Settings ("io.elementary.settings-daemon.system-updates");
    }

    private CurrentState current_state;
    private UpdateDetails update_details;

    private Pk.Task task;
    private Pk.PackageSack? available_updates = null;
    private GLib.Cancellable cancellable;
    private Error? last_error = null;

    construct {
        current_state = {
            UP_TO_DATE,
            ""
        };

        update_details = {
            {},
            0
        };

        task = new Pk.Task () {
            only_download = true
        };

        cancellable = new GLib.Cancellable ();

        check_for_updates.begin ();

        Timeout.add_seconds ((uint) settings.get_int64 ("refresh-interval"), () => {
            check_for_updates.begin ();
            return Source.CONTINUE;
        });
    }

    public async void check_for_updates (bool force = false) throws DBusError, IOError {
        if (current_state.state != UP_TO_DATE && current_state.state != AVAILABLE && !force) {
            return;
        }

        update_state (CHECKING);

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

            foreach (var package in available_updates.get_array ()) {
                package_names += package.get_name ();
            }

            update_details = {
                package_names,
                0 //FIXME: Is there a way to get update size from PackageKit
            };

            var notification = new Notification (_("Update Available"));
            notification.set_body (_("A system update is available"));
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

        cancellable.reset ();

        update_state (DOWNLOADING);

        try {
            yield task.update_packages_async (available_updates.get_ids (), cancellable, progress_callback);

            Pk.offline_trigger (REBOOT);

            var notification = new Notification (_("Restart Required"));
            notification.set_body (_("Please restart your system to finalize updates"));
            notification.set_icon (new ThemedIcon ("system-reboot"));
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

            GLib.Application.get_default ().send_notification (null, notification);

            update_state (RESTART_REQUIRED);
        } catch (IOError.CANCELLED e) {
            debug ("Updates were cancelled");
            check_for_updates.begin (true);
        } catch (Error e) {
            critical ("Failed to download available updates: %s", e.message);

            var notification = new Notification (_("Update failed"));
            notification.set_body (_("An Error occured while trying to update your system"));
            notification.set_icon (new ThemedIcon ("dialog-error"));
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ERROR_ACTION);

            GLib.Application.get_default ().send_notification (null, notification);

            last_error = e;

            //This will also flush any already downloaded updates and disable the offline trigger (I think)
            check_for_updates.begin (true);
        }
    }

    public void cancel () throws DBusError, IOError {
        cancellable.cancel ();
    }

    [DBus (visible=false)]
    public void show_error_details () {
        if (last_error == null) {
            return;
        }

        var message_dialog = new Granite.MessageDialog (
            _("Failed to download updates"),
            _("This may have been caused by sideloaded or manually compiled software, a third-party software source, or a package manager error. Manually refreshing updates may resolve the issue."),
            new ThemedIcon ("dialog-error")
        );
        message_dialog.add_button (_("Refresh Updates"), Gtk.ResponseType.ACCEPT);

        message_dialog.show_error_details (last_error.message);

        message_dialog.response.connect ((response_type) => {
            if (response_type == Gtk.ResponseType.ACCEPT) {
                check_for_updates.begin (true);
            }

            message_dialog.destroy ();
        });

        message_dialog.present ();
    }

    private void progress_callback (Pk.Progress progress, Pk.ProgressType progress_type) {
        update_state (current_state.state, status_to_title (progress.status));
    }

    private void update_state (State state, string message = "") {
        current_state = {
            state,
            message
        };

        state_changed ();
    }

    private unowned string status_to_title (Pk.Status status) {
        // From https://github.com/elementary/appcenter/blob/master/src/Core/ChangeInformation.vala#L51
        switch (status) {
            case Pk.Status.SETUP:
                return _("Starting");
            case Pk.Status.WAIT:
                return _("Waiting");
            case Pk.Status.RUNNING:
                return _("Running");
            case Pk.Status.QUERY:
                return _("Querying");
            case Pk.Status.INFO:
                return _("Getting information");
            case Pk.Status.REMOVE:
                return _("Removing packages");
            case Pk.Status.DOWNLOAD:
                return _("Downloading");
            case Pk.Status.REFRESH_CACHE:
                return _("Refreshing software list");
            case Pk.Status.UPDATE:
                return _("Installing updates");
            case Pk.Status.CLEANUP:
                return _("Cleaning up packages");
            case Pk.Status.OBSOLETE:
                return _("Obsoleting packages");
            case Pk.Status.DEP_RESOLVE:
                return _("Resolving dependencies");
            case Pk.Status.SIG_CHECK:
                return _("Checking signatures");
            case Pk.Status.TEST_COMMIT:
                return _("Testing changes");
            case Pk.Status.COMMIT:
                return _("Committing changes");
            case Pk.Status.REQUEST:
                return _("Requesting data");
            case Pk.Status.FINISHED:
                return _("Finished");
            case Pk.Status.CANCEL:
                return _("Cancelling");
            case Pk.Status.DOWNLOAD_REPOSITORY:
                return _("Downloading repository information");
            case Pk.Status.DOWNLOAD_PACKAGELIST:
                return _("Downloading list of packages");
            case Pk.Status.DOWNLOAD_FILELIST:
                return _("Downloading file lists");
            case Pk.Status.DOWNLOAD_CHANGELOG:
                return _("Downloading lists of changes");
            case Pk.Status.DOWNLOAD_GROUP:
                return _("Downloading groups");
            case Pk.Status.DOWNLOAD_UPDATEINFO:
                return _("Downloading update information");
            case Pk.Status.REPACKAGING:
                return _("Repackaging files");
            case Pk.Status.LOADING_CACHE:
                return _("Loading cache");
            case Pk.Status.SCAN_APPLICATIONS:
                return _("Scanning applications");
            case Pk.Status.GENERATE_PACKAGE_LIST:
                return _("Generating package lists");
            case Pk.Status.WAITING_FOR_LOCK:
                return _("Waiting for package manager lock");
            case Pk.Status.WAITING_FOR_AUTH:
                return _("Waiting for authentication");
            case Pk.Status.SCAN_PROCESS_LIST:
                return _("Updating running applications");
            case Pk.Status.CHECK_EXECUTABLE_FILES:
                return _("Checking applications in use");
            case Pk.Status.CHECK_LIBRARIES:
                return _("Checking libraries in use");
            case Pk.Status.COPY_FILES:
                return _("Copying files");
            case Pk.Status.INSTALL:
            default:
                return _("Installing");
        }
    }

    public async CurrentState get_current_state () throws DBusError, IOError {
        return current_state;
    }

    public async UpdateDetails get_update_details () throws DBusError, IOError {
        return update_details;
    }
}

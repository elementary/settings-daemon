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

    private CurrentState current_state;
    private UpdateDetails update_details;

    private Pk.Task task;
    private Pk.PackageSack? available_updates = null;
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

        check_for_updates.begin ();
    }

    public async void check_for_updates (bool force = false) {
        if (current_state.state != UP_TO_DATE && !force) {
            return;
        }

        update_state (CHECKING);

        try {
            yield task.refresh_cache_async (false, null, progress_callback);
        } catch (Error e) {
            warning ("Failed to refresh cache: %s", e.message);
        }

        try {
            available_updates = (yield task.get_updates_async (Pk.Filter.NONE, null, progress_callback)).get_package_sack ();

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

        update_state (DOWNLOADING);

        try {
            var result = yield task.update_packages_async (available_updates.get_ids (), null, progress_callback);

            Pk.offline_trigger (REBOOT);

            update_state (RESTART_REQUIRED);
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

/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Backends.SystemDSystemUpdate : Object, SystemUpdateProvider {
    private const string NOTIFICATION_ID = "system-update";

    private PkUtils.CurrentState current_state;
    private UpdateDetails update_details;

    private Utils.SysupdateTarget target;
    private Cancellable? current_cancellable;

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

        target = new Utils.SysupdateTarget (Sysupdate.Target.HOST_PATH);
    }

    public async void check_for_updates (bool force, bool notify) throws DBusError, IOError {
        if (SettingsDaemon.Utils.is_running_in_demo_mode () && !force) {
            return;
        }

        if (current_state.state != UP_TO_DATE && current_state.state != AVAILABLE && !force) {
            return;
        }

        update_state (CHECKING, _("Checking for updates"));

        /* First check if there is an even newer version than anything we have installed */
        string? new_version = null;
        try {
            new_version = yield target.check_new ();
        } catch (Error e) {
            critical ("Failed to check for updates: %s", e.message);
            update_state (UP_TO_DATE);
            return;
        }

        if (new_version != null) {
            update_details = {
                { new_version },
                0,
                { Pk.Info.IMPORTANT }
            };

            update_state (AVAILABLE);
            return;
        }

        /* Then check if we maybe have a newer version already installed but not booted into */
        try {
            if (yield target.has_newer_unapplied_version ()) {
                update_state (RESTART_REQUIRED);
                return;
            }
        } catch (Error e) {
            critical ("Failed to check for newer unapplied version: %s", e.message);
        }

        update_state (UP_TO_DATE);
    }

    public async void update () throws DBusError, IOError {
        if (current_state.state != AVAILABLE) {
            return;
        }

        update_state (DOWNLOADING);

        current_cancellable = new Cancellable ();

        try {
            yield target.update (NEWEST, current_cancellable, progress_callback);
        } catch (Error e) {
            critical ("Failed to update: %s", e.message);
            send_error (e.message);
            return;
        }

        update_state (RESTART_REQUIRED);
    }

    public void cancel () throws DBusError, IOError {
        if (current_state.state != DOWNLOADING) {
            return;
        }

        current_cancellable.cancel ();
    }

    private void progress_callback (string message, uint percentage) {
        update_state (
            DOWNLOADING,
            message,
            percentage,
            0
        );
    }

    private void send_error (string message) {
        var notification = new Notification (_("System updates couldn't be installed"));
        notification.set_body (_("An error occurred while trying to update your system"));
        notification.set_icon (new ThemedIcon ("dialog-error"));
        notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

        GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);

        update_state (ERROR, message);
    }

    private void update_state (
        PkUtils.State state,
        string message = "",
        uint percentage = 0,
        uint64 download_size_remaining = 0
    ) {
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

    public async int64 get_last_refresh_time () throws DBusError, IOError {
        return 0;
    }
}

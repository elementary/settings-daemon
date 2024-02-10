/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

[DBus (name="io.elementary.settings_daemon.Drivers")]
public class SettingsDaemon.Backends.UbuntuDrivers : Object {
    private const string NOTIFICATION_ID = "drivers";

    public signal void state_changed ();

    private PkUtils.CurrentState current_state;
    private HashTable<string, GenericSet<string>> available_drivers;

    private Pk.Task task;
    private GLib.Cancellable cancellable;

    construct {
        current_state = {
            UP_TO_DATE,
            ""
        };

        available_drivers = new HashTable<string, GenericSet<string>> (str_hash, str_equal);

        task = new Pk.Task () {
            only_download = true
        };

        cancellable = new GLib.Cancellable ();

        check_for_drivers.begin (true);
    }

    private async bool get_drivers_output (Cancellable? cancellable = null, out string? output = null) {
        output = null;
        string? drivers_exec_path = Environment.find_program_in_path ("ubuntu-drivers");
        if (drivers_exec_path == null) {
            return false;
        }

        Subprocess command;
        try {
            command = new Subprocess (SubprocessFlags.STDOUT_PIPE, drivers_exec_path, "list");
            yield command.communicate_utf8_async (null, cancellable, out output, null);
        } catch (Error e) {
            critical ("Failed to launch ubuntu-drivers: %s", e.message);
            return false;
        }

        return command.get_exit_status () == 0;
    }

    public async void check_for_drivers (bool notify) throws DBusError, IOError {
        if (current_state.state != UP_TO_DATE && current_state.state != AVAILABLE) {
            return;
        }

        update_state (CHECKING);
        available_drivers.remove_all ();

        string? command_output;
        var result = yield get_drivers_output (cancellable, out command_output);
        if (!result || command_output == null) {
            update_state (UP_TO_DATE);
            critical ("Failed to get ubuntu-drivers output");
            return;
        }

        string[] tokens = command_output.split ("\n");
        foreach (unowned string package_name in tokens) {
            if (package_name.strip () == "") {
                continue;
            }

            // ubuntu-drivers returns lines like the following for dkms packages:
            // backport-iwlwifi-dkms, (kernel modules provided by backport-iwlwifi-dkms)
            // nvidia-driver-470, (kernel modules provided by linux-modules-nvidia-470-generic-hwe-20.04)
            // we want to install both packages if they're different

            string[] parts = package_name.split (",");
            // Get the driver part (before the comma)
            var package_names = new GenericSet<string> (str_hash, str_equal);
            package_names.add (parts[0]);

            if (parts.length > 1) {
                if (parts[1].contains ("kernel modules provided by")) {
                    string[] kernel_module_parts = parts[1].split (" ");
                    // Get the remainder of the string after the last space
                    var last_part = kernel_module_parts[kernel_module_parts.length - 1];
                    // Strip off the trailing bracket
                    last_part = last_part.replace (")", "");

                    package_names.add (last_part);
                } else {
                    warning ("Unrecognised line from ubuntu-drivers, needs checking: %s", package_name);
                }
            }

            available_drivers[package_name] = package_names;
        }

        if (available_drivers.length == 0) {
            update_state (UP_TO_DATE);
            return;
        }

        update_state (AVAILABLE);

        if (notify) {
            var notification = new Notification (_("Drivers available"));
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);
            notification.set_body (_("For your system are drivers available"));
            notification.set_icon (new ThemedIcon ("software-update-available"));

            GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);
        }
    }

    public async void install (string pkg_id) throws DBusError, IOError {
        cancellable.reset ();

        update_state (DOWNLOADING);

        string[] package_names = {};
        available_drivers[pkg_id].@foreach ((package_name) => package_names += package_name);

        try {
            var results = yield task.install_packages_async (package_names, cancellable, progress_callback);

            if (results.get_exit_code () == CANCELLED) {
                debug ("Installation was cancelled");
                return;
            }

            Pk.offline_trigger (REBOOT);

            var notification = new Notification (_("Restart required"));
            notification.set_body (_("Please restart your system to finalize driver installation"));
            notification.set_icon (new ThemedIcon ("system-reboot"));
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

            GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);

            update_state (RESTART_REQUIRED);
        } catch (Error e) {
            critical ("Failed to install driver: %s", e.message);
            send_error (e.message);
        }
    }

    public void cancel () throws DBusError, IOError {
        cancellable.cancel ();
    }

    private void progress_callback (Pk.Progress progress, Pk.ProgressType progress_type) {
        update_state (current_state.state, PkUtils.status_to_title (progress.status));
    }

    private void send_error (string message) {
        var notification = new Notification (_("A driver couldn't be installed"));
        notification.set_body (_("An error occurred while trying to install a driver"));
        notification.set_icon (new ThemedIcon ("dialog-error"));
        notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

        GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);

        update_state (ERROR, message);
    }

    private void update_state (PkUtils.State state, string message = "") {
        current_state = {
            state,
            message
        };

        state_changed ();
    }

    public async PkUtils.CurrentState get_current_state () throws DBusError, IOError {
        return current_state;
    }

    public async string[] get_available_drivers () throws DBusError, IOError {
        return available_drivers.get_keys_as_array ();
    }
}
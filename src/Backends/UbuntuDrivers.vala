/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

[DBus (name="io.elementary.settings_daemon.Drivers")]
public class SettingsDaemon.Backends.UbuntuDrivers : Object {
    private const string NOTIFICATION_ID = "drivers";

    private class Device : Object {
        public string name;
        public HashTable<string, bool> available_drivers_with_installed = new HashTable<string, bool> (str_hash, str_equal);
    }

    public signal void state_changed ();

    private PkUtils.CurrentState current_state;
    private HashTable<string, GenericArray<string>> available_drivers;
    private HashTable<string, Device> devices_by_drivers;
    private Device[] devices = {};

    private Pk.Task task;
    private GLib.Cancellable cancellable;

    construct {
        current_state = {
            UP_TO_DATE,
            "",
            0,
            0
        };

        available_drivers = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
        devices_by_drivers = new HashTable<string, Device> (str_hash, str_equal);

        task = new Pk.Task ();

        cancellable = new GLib.Cancellable ();

        check_for_drivers.begin (true);
    }

    private async string? get_drivers_output (string verb) {
        string? drivers_exec_path = Environment.find_program_in_path ("ubuntu-drivers");
        if (drivers_exec_path == null) {
            return null;
        }

        try {
            var command = new Subprocess (SubprocessFlags.STDOUT_PIPE, drivers_exec_path, verb);

            string output;
            yield command.communicate_utf8_async (null, cancellable, out output, null);

            return output;
        } catch (Error e) {
            critical ("Failed to launch ubuntu-drivers: %s", e.message);
            return null;
        }
    }

    private async void check_devices () {
        var output = yield get_drivers_output ("devices");
        if (output == null) {
            critical ("Failed to get ubuntu-drivers output");
            return;
        }

        string[] tokens = output.split ("\n");

        Device? current_device = null;
        foreach (var token in tokens) {
            if ("==" in token) {
                current_device = new Device ();
                devices += current_device;
                continue;
            }

            if (current_device == null) {
                continue;
            }

            if (token.has_prefix ("model")) {
                var normalized_token = token.splice (0, 11);
                current_device.name = normalized_token;
                continue;
            }

            if (token.has_prefix ("driver")) {
                var normalized_token = token.splice (0, 11);
                var split_token = normalized_token.split (" - ");
                var driver = split_token[0];
                devices_by_drivers[driver] = current_device;
                continue;
            }
        }
    }

    public async void check_for_drivers (bool notify) throws DBusError, IOError {
        update_state (CHECKING);

        available_drivers.remove_all ();

        yield check_devices ();

        var command_output = yield get_drivers_output ("list");
        if (command_output == null) {
            update_state (UP_TO_DATE);
            critical ("Failed to get ubuntu-drivers output");
            return;
        }

        string[] tokens = command_output.split ("\n");
        foreach (unowned string line in tokens) {
            if (line.strip () == "") {
                continue;
            }

            // Filter out the nvidia server drivers
            if (line.contains ("nvidia") && line.contains ("-server")) {
                continue;
            }

            // ubuntu-drivers returns lines like the following for dkms packages:
            // backport-iwlwifi-dkms, (kernel modules provided by backport-iwlwifi-dkms)
            // nvidia-driver-470, (kernel modules provided by linux-modules-nvidia-470-generic-hwe-20.04)
            // we want to install both packages if they're different

            string[] parts = line.split (",");

            var driver = parts[0];

            if (driver == null || !(driver in devices_by_drivers)) {
                continue;
            }

            // Get the driver part (before the comma)
            string[] package_names = {};

            package_names += driver;

            if (parts.length > 1) {
                if (parts[1].contains ("kernel modules provided by")) {
                    string[] kernel_module_parts = parts[1].split (" ");
                    // Get the remainder of the string after the last space
                    var last_part = kernel_module_parts[kernel_module_parts.length - 1];
                    // Strip off the trailing bracket
                    last_part = last_part.replace (")", "");

                    if (!(last_part in package_names)) {
                        package_names += last_part;
                    }
                } else {
                    warning ("Unrecognised line from ubuntu-drivers, needs checking: %s", line);
                }
            }

            available_drivers[driver] = yield update_installed (driver, package_names);
        }

        if (available_drivers.length == 0) {
            update_state (UP_TO_DATE);
            return;
        }

        update_state (AVAILABLE);

        if (notify) {
            var title = ngettext ("Driver Available", "Drivers Available", available_drivers.length);
            var body = ngettext (
                "%u driver is available for your hardware",
                "%u drivers are available for your hardware",
                available_drivers.length
            );

            var notification = new Notification (title);
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);
            notification.set_body (body.printf (available_drivers.length));
            notification.set_icon (new ThemedIcon ("software-update-available"));

            GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);
        }
    }

    private async GenericArray<string> update_installed (string driver, string[] package_names) {
        var array = new GenericArray<string> ();
        try {
            var result = yield task.resolve_async (Pk.Filter.NONE, package_names, null, () => {});

            var packages = result.get_package_array ();

            bool all_installed = true;
            foreach (var package in packages) {
                array.add (package.package_id);

                if (!(driver in devices_by_drivers)) {
                    continue;
                }

                if (all_installed && (Pk.Info.INSTALLED == package.info)) {
                    devices_by_drivers[driver].available_drivers_with_installed[driver] = true;
                } else {
                    all_installed = false;
                    devices_by_drivers[driver].available_drivers_with_installed[driver] = false;
                }
            }
        } catch (Error e) {
            critical ("Failed to get package details, treating as not installed: %s", e.message);
        }

        return array;
    }

    public async void install (string pkg_name) throws DBusError, IOError {
        if (!(pkg_name in available_drivers)) {
            critical ("Driver not found");
            return;
        }

        if (current_state.state != AVAILABLE) {
            warning ("No drivers available, or already downloading a driver.");
            return;
        }

        cancellable.reset ();

        update_state (DOWNLOADING);

        try {
            string[] pkgs = available_drivers[pkg_name].data; // It seems arrays are imediately freed with async methods so this prevents a seg fault
            var results = yield task.install_packages_async (pkgs, cancellable, progress_callback);

            if (results.get_exit_code () == CANCELLED) {
                debug ("Installation was cancelled");
                update_state (AVAILABLE);
                return;
            }

            foreach (var driver in available_drivers.get_keys ()) {
                string[] driver_pkgs = available_drivers[driver].data;
                yield update_installed (driver, driver_pkgs);
            }

            var notification = new Notification (_("Restart required"));
            notification.set_body (_("Please restart your system to finalize driver installation"));
            notification.set_icon (new ThemedIcon ("system-reboot"));
            notification.set_default_action (Application.ACTION_PREFIX + Application.SHOW_UPDATES_ACTION);

            GLib.Application.get_default ().send_notification (NOTIFICATION_ID, notification);

            update_state (AVAILABLE);
        } catch (Error e) {
            critical ("Failed to install driver: %s", e.message);
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
        var notification = new Notification (_("A driver couldn't be installed"));
        notification.set_body (_("An error occurred while trying to install a driver"));
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

    public async HashTable<string, HashTable<string, bool>> get_available_drivers () throws DBusError, IOError {
        var map = new HashTable<string, HashTable<string, bool>> (str_hash, str_equal);

        foreach (var device in devices) {
            map[device.name] = device.available_drivers_with_installed;
        }

        return map;
    }
}

/*
 * Copyright 2024 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class SettingsDaemon.Backends.DisplaySettings : GLib.Object {
    private string monitors_path;
    private FileMonitor? file_monitor;

    construct {
        monitors_path = Path.build_filename (GLib.Environment.get_user_config_dir (), "monitors.xml");
        sync_monitors_to_greeter ();

        var file = File.new_for_path (monitors_path);
        try {
            file_monitor = file.monitor (GLib.FileMonitorFlags.NONE);
            file_monitor.changed.connect ((file, other_file, type) => {
                if (type == FileMonitorEvent.CHANGES_DONE_HINT) {
                    sync_monitors_to_greeter ();
                }
            });
        } catch (Error e) {
            critical ("Couldn't obtain FileMonitor for %s", monitors_path);
            file_monitor = null;
        }
    }

    private void sync_monitors_to_greeter () {
        if (!FileUtils.test (monitors_path, EXISTS)) {
            critical ("%s not found", monitors_path);
            return;
        }

        warning ("OwO");

        var source = File.new_for_path (monitors_path);
        var greeter_data_dir = Environment.get_variable ("XDG_GREETER_DATA_DIR") ?? Path.build_filename ("/var/lib/lightdm-data", Environment.get_user_name ());
        var folder = File.new_for_path (greeter_data_dir);
        var dest = folder.get_child ("monitors.xml");

        try {
            if (!folder.query_exists ()) {
                folder.make_directory_with_parents ();
            }

            source.copy (dest, OVERWRITE | ALL_METADATA);
            // Ensure monitors.xml is readable by greeter user (owner rw, others r)
            FileUtils.chmod (dest.get_path (), 0604);
        } catch (Error e) {
            warning (e.message);
        }
    }
}

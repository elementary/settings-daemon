/*
 * Copyright 2024 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class SettingsDaemon.Backends.DisplaySettings : GLib.Object {
    private string monitors_path;
    private FileMonitor? file_monitor;
    private Polkit.Permission? permission = null;

    construct {
        monitors_path = Path.build_filename (GLib.Environment.get_user_config_dir (), "monitors.xml");
        sync_monitors_to_system ();

        var file = File.new_for_path (monitors_path);
        try {
            file_monitor = file.monitor (GLib.FileMonitorFlags.NONE);
            file_monitor.changed.connect ((file, other_file, type) => {
                if (type == FileMonitorEvent.CHANGES_DONE_HINT) {
                    sync_monitors_to_system ();
                }
            });
        } catch (Error e) {
            critical ("Couldn't obtain FileMonitor for %s", monitors_path);
            file_monitor = null;
        }
    }

    private void sync_monitors_to_system () {
        if (!FileUtils.test (monitors_path, EXISTS)) {
            critical ("%s not found", monitors_path);
            return;
        }

        if (permission == null) {
            try {
                permission = new Polkit.Permission.sync (
                    "io.elementary.settings-daemon.administration",
                    new Polkit.UnixProcess (Posix.getpid ())
                );
            } catch (Error e) {
                warning ("Can't get permission to change display settings without prompting for admin: %s", e.message);
            }
        }

        var source = File.new_for_path (monitors_path);

        foreach (var dir in Environment.get_system_config_dirs ()) {
            if (!FileUtils.test (dir, EXISTS)) {
                continue;
            }

            var dest = File.new_for_path (dir).get_child ("monitors.xml");
    
            try {
                source.copy (dest, OVERWRITE | ALL_METADATA);
                //  Ensure monitors.xml is readable by greeter user (owner rw, others r)
                //  FileUtils.chmod (dest.get_path (), 0604);
            } catch (Error e) {
                warning (e.message);
            }

            break;
        }
    }
}

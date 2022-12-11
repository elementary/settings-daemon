/*
* Copyright 2021 elementary, Inc. (https://elementary.io)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 3 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
*/

[DBus (name = "org.freedesktop.systemd1.Manager")]
public interface SystemdManager : Object {
    public abstract async string get_unit_file_state (string unit_file) throws Error;
    public abstract async void enable_unit_files (string[] unit_files, bool runtime, bool replace) throws Error;
    public abstract async void start_unit (string name, string mode) throws Error;
}

public class SettingsDaemon.Backends.Housekeeping : Object {
    private Settings housekeeping_settings;
    private SystemdManager? systemd;

    construct {
        housekeeping_settings = new Settings ("io.elementary.settings-daemon.housekeeping");
        housekeeping_settings.changed.connect (() => {
            enable_systemd_tmpfiles.begin ();
            write_systemd_tmpfiles_config.begin ();
        });

        if (housekeeping_settings.get_boolean ("cleanup-downloads-folder")) {
            enable_systemd_tmpfiles.begin ();
        }

        write_systemd_tmpfiles_config.begin ();
    }

    // The systemd-tmpfiles-clean user timer that runs every day and cleans up files based on user config files
    // is disabled by default (at least on Ubuntu 20.04), so we have some code to check and enable it if necessary
    private async void enable_systemd_tmpfiles () {
        if (systemd == null) {
            try {
                systemd = yield Bus.get_proxy (
                    BusType.SESSION,
                    "org.freedesktop.systemd1",
                    "/org/freedesktop/systemd1"
                );
            } catch (Error e) {
                warning ("Unable to connect to systemd to see if systemd-tmpfiles service is enabled: %s", e.message);
                return;
            }
        }

        try {
            // Already enabled, nothing to do
            if ((yield systemd.get_unit_file_state ("systemd-tmpfiles-clean.timer")) == "enabled") {
                return;
            }

            yield systemd.enable_unit_files ({"systemd-tmpfiles-clean.timer"}, false, false);
            yield systemd.start_unit ("systemd-tmpfiles-clean.timer", "fail");
        } catch (Error e) {
            warning ("Error getting or setting systemd-tmpfiles enabled state: %s", e.message);
        }
    }

    // Write (or delete) a config file in ~/.config/user-tmpfiles.d to configure the systemd timer for cleaning up the user's
    // downloads folder based on the configured age in GSettings
    private async void write_systemd_tmpfiles_config () {
        var config_path = Path.build_filename (
            Environment.get_user_config_dir (),
            "user-tmpfiles.d",
            "io.elementary.settings-daemon.downloads-folder.conf"
        );

        var downloads_cleanup_enabled = housekeeping_settings.get_boolean ("cleanup-downloads-folder");

        var config_file = File.new_for_path (config_path);
        if (!config_file.get_parent ().query_exists ()) {
            if (!downloads_cleanup_enabled) {
                // No point continuing if cleanup isn't enabled
                return;
            }

            try {
                config_file.get_parent ().make_directory_with_parents ();
            } catch (Error e) {
                warning ("Error creating directory for systemd-tmpfiles: %s", e.message);
                return;
            }
        }

        int downloads_cleanup_days = housekeeping_settings.get_int ("old-files-age");

        var downloads_folder = Environment.get_user_special_dir (
            UserDirectory.DOWNLOAD
        );

        var home_folder = Environment.get_home_dir ();
        if (File.new_for_path (home_folder).equal (File.new_for_path (downloads_folder))) {
            // TODO: Possibly throw a notification as a warning here? This will currently just silently fail
            // and no downloads will be cleaned up, despite the setting being enabled
            warning ("Downloads folder seems to point to home directory, not enabling cleanup");
            downloads_cleanup_enabled = false;
        }

        // Delete the systemd-tmpfiles config if download cleanup is disabled
        if (!downloads_cleanup_enabled || downloads_cleanup_days < 1) {
            try {
                yield config_file.delete_async ();
            } catch (Error e) {
                if (!(e is IOError.NOT_FOUND)) {
                    warning ("Unable to delete systemd-tmpfiles config: %s", e.message);
                }
            }

            return;
        }

        FileIOStream config_stream;
        try {
            config_stream = yield config_file.replace_readwrite_async (null, false, FileCreateFlags.NONE);
        } catch (Error e) {
            warning ("Unable to open systemd-tmpfiles config file for writing: %s", e.message);
            return;
        }

        // See https://www.freedesktop.org/software/systemd/man/tmpfiles.d.html for details
        // Results in a config line like:
        // e "/home/david/Downloads" - - - 30d
        string config = "e \"%s\" - - - %dd".printf (downloads_folder, downloads_cleanup_days);

        FileOutputStream os = config_stream.output_stream as FileOutputStream;
        try {
            yield os.write_all_async (config.data, Priority.DEFAULT, null, null);
        } catch (Error e) {
            warning ("Unable to write systemd-tmpfiles config: %s", e.message);
        }
    }
}

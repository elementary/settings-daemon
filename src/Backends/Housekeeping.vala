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

        if (
            housekeeping_settings.get_boolean ("cleanup-downloads-folder") ||
            housekeeping_settings.get_boolean ("cleanup-screenshots-folder") ||
            housekeeping_settings.get_boolean ("cleanup-temp-folder") ||
            housekeeping_settings.get_boolean ("cleanup-trash-folder")
        ) {
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

        var cleanup_config = new CleanupConfig (housekeeping_settings);

        var config_file = File.new_for_path (config_path);
        if (!config_file.get_parent ().query_exists ()) {
            if (cleanup_config.is_disabled) {
                // No point continuing if cleanup is disabled
                return;
            }

            try {
                config_file.get_parent ().make_directory_with_parents ();
            } catch (Error e) {
                warning ("Error creating directory for systemd-tmpfiles: %s", e.message);
                return;
            }
        }

        // Delete the systemd-tmpfiles config if cleanup is disabled
        if (cleanup_config.is_disabled) {
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

        FileOutputStream os = config_stream.output_stream as FileOutputStream;
        try {
            yield os.write_all_async (cleanup_config.data (), Priority.DEFAULT, null, null);
        } catch (Error e) {
            warning ("Unable to write systemd-tmpfiles config: %s", e.message);
        }
    }

    private class CleanupConfig : Object {
        public bool clean_downloads { private get; public construct; }
        public bool clean_screenshots { private get; public construct; }
        public bool clean_temp { private get; public construct; }
        public bool clean_trash { private get; public construct; }
        public int clean_after_days { private get; public construct; }

        public bool is_disabled { get {
            return (!clean_downloads && !clean_screenshots) || clean_after_days < 1;
        }}

        public CleanupConfig (Settings settings) {
            Object (
                clean_downloads: settings.get_boolean ("cleanup-downloads-folder")
                    && downloads_are_not_home (),
                clean_screenshots: settings.get_boolean ("cleanup-screenshots-folder"),
                clean_temp: settings.get_boolean ("cleanup-temp-folder"),
                clean_trash: settings.get_boolean ("cleanup-trash-folder"),
                clean_after_days: settings.get_int ("old-files-age")
            );
        }

        private static bool downloads_are_not_home () {
            var home_dir = Environment.get_home_dir ();
            var home = File.new_for_path (home_dir);
            var downloads_dir = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
            var downloads = File.new_for_path (downloads_dir);
            return !home.equal (downloads);
        }

        public uint8[] data () {
            // See https://www.freedesktop.org/software/systemd/man/tmpfiles.d.html for details
            // Results in a config line like:
            // e "/home/david/Downloads" - - - 30d
            var template = "e \"%s\" - - - %dd";
            string[] lines = {};

            if (clean_downloads) {
                var downloads_dir = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
                lines += template.printf (downloads_dir, clean_after_days);
            }

            if (clean_screenshots) {
                var pictures_dir = Environment.get_user_special_dir (UserDirectory.PICTURES);
                var screenshots_dir = Path.build_filename (pictures_dir, dgettext ("gala", "Screenshots"));
                lines += template.printf (screenshots_dir, clean_after_days);
            }

            if (clean_temp) {
                var temp_dir = Environment.get_tmp_dir ();
                lines += template.printf (temp_dir, clean_after_days);
            }

            if (clean_trash) {
                var user_data_dir = Environment.get_user_data_dir ();
                var trash_files_dir = Path.build_filename (user_data_dir, "Trash", "files");
                var trash_info_dir = Path.build_filename (user_data_dir, "Trash", "info");
                lines += template.printf (trash_files_dir, clean_after_days);
                lines += template.printf (trash_info_dir, clean_after_days);
            }

            return string.joinv ("\n", lines).data;
        }
    }
}

/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
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
 */

public class SettingsDaemon.Backends.InterfaceSettings : GLib.Object {
    private const string CURSOR_BLINK = "cursor-blink";
    private const string CURSOR_BLINK_TIME = "cursor-blink-time";
    private const string CURSOR_BLINK_TIMEOUT = "cursor-blink-timeout";
    private const string CURSOR_SIZE = "cursor-size";
    private const string LOCATE_POINTER = "locate-pointer";
    private const string TEXT_SCALING_FACTOR = "text-scaling-factor";

    private const string PICTURE_OPTIONS = "picture-options";
    private const string PRIMARY_COLOR = "primary-color";
    private const string PICTURE_URI = "picture-uri";

    private const string DOCUMENT_FONT_NAME = "document-font-name";
    private const string FONT_NAME = "font-name";
    private const string MONOSPACE_FONT_NAME = "monospace-font-name";

    private const string LAST_COORDINATES = "last-coordinates";
    private const string ORIENTATION_LOCK = "orientation-lock";
    private const string PREFER_DARK_SCHEDULE = "prefer-dark-schedule";
    private const string PREFER_DARK_SCHEDULE_FROM = "prefer-dark-schedule-from";
    private const string PREFER_DARK_SCHEDULE_TO = "prefer-dark-schedule-to";

    public unowned AccountsService accounts_service { get; construct; }
    public unowned DisplayManager.AccountsService display_manager_accounts_service { get; construct; }

    private GLib.Settings interface_settings;
    private GLib.Settings background_settings;
    private GLib.Settings settings_daemon_settings;
    private GLib.Settings touchscreen_settings;

    public InterfaceSettings (AccountsService accounts_service, DisplayManager.AccountsService display_manager_accounts_service) {
        Object (
            accounts_service: accounts_service,
            display_manager_accounts_service: display_manager_accounts_service
        );
    }

    construct {
        interface_settings = new GLib.Settings ("org.gnome.desktop.interface");
        background_settings = new GLib.Settings ("org.gnome.desktop.background");
        settings_daemon_settings = new GLib.Settings ("io.elementary.settings-daemon.prefers-color-scheme");
        touchscreen_settings = new GLib.Settings ("org.gnome.settings-daemon.peripherals.touchscreen");

        sync_gsettings_to_accountsservice ();

        interface_settings.changed.connect ((key) => {
            if (key == CURSOR_BLINK ||
                key == CURSOR_BLINK_TIME ||
                key == CURSOR_BLINK_TIMEOUT ||
                key == CURSOR_SIZE ||
                key == LOCATE_POINTER ||
                key == TEXT_SCALING_FACTOR ||
                key == DOCUMENT_FONT_NAME ||
                key == FONT_NAME ||
                key == MONOSPACE_FONT_NAME) {
                sync_gsettings_to_accountsservice ();
            }
        });

        background_settings.changed.connect ((key) => {
            if (key == PICTURE_OPTIONS ||
                key == PRIMARY_COLOR) {
                sync_gsettings_to_accountsservice ();
                return;
            }

            if (key == PICTURE_URI) {
                sync_background_to_greeter ();
            }
        });

        settings_daemon_settings.changed.connect ((key) => {
            if (key == LAST_COORDINATES ||
                key == PREFER_DARK_SCHEDULE ||
                key == PREFER_DARK_SCHEDULE_FROM ||
                key == PREFER_DARK_SCHEDULE_TO) {
                sync_gsettings_to_accountsservice ();
            }
        });

        touchscreen_settings.changed.connect (sync_gsettings_to_accountsservice);
    }

    private void sync_gsettings_to_accountsservice () {
        accounts_service.cursor_blink = interface_settings.get_boolean (CURSOR_BLINK);
        accounts_service.cursor_blink_time = interface_settings.get_int (CURSOR_BLINK_TIME);
        accounts_service.cursor_blink_timeout = interface_settings.get_int (CURSOR_BLINK_TIMEOUT);
        accounts_service.cursor_size = interface_settings.get_int (CURSOR_SIZE);
        accounts_service.locate_pointer = interface_settings.get_boolean (LOCATE_POINTER);
        accounts_service.text_scaling_factor = interface_settings.get_double (TEXT_SCALING_FACTOR);

        accounts_service.picture_options = background_settings.get_enum (PICTURE_OPTIONS);
        accounts_service.primary_color = background_settings.get_string (PRIMARY_COLOR);

        accounts_service.document_font_name = interface_settings.get_string (DOCUMENT_FONT_NAME);
        accounts_service.font_name = interface_settings.get_string (FONT_NAME);
        accounts_service.monospace_font_name = interface_settings.get_string (MONOSPACE_FONT_NAME);

        var last_coordinates_value = settings_daemon_settings.get_value (LAST_COORDINATES);
        if (last_coordinates_value.is_of_type (GLib.VariantType.TUPLE)) {
            double latitude;
            double longitude;

            last_coordinates_value.@get ("(dd)", out latitude, out longitude);

            accounts_service.prefer_dark_last_coordinates = AccountsService.Coordinates () {
                latitude = latitude,
                longitude = longitude
            };
        } else {
            warning ("Unknown prefer dark coordinates type, unable to save to AccountsService");
        }

        accounts_service.prefer_dark_schedule = settings_daemon_settings.get_enum (PREFER_DARK_SCHEDULE);
        accounts_service.prefer_dark_schedule_from = settings_daemon_settings.get_double (PREFER_DARK_SCHEDULE_FROM);
        accounts_service.prefer_dark_schedule_to = settings_daemon_settings.get_double (PREFER_DARK_SCHEDULE_TO);

        accounts_service.orientation_lock = touchscreen_settings.get_boolean (ORIENTATION_LOCK);
    }

    private void sync_background_to_greeter () {
        var source = File.new_for_uri (background_settings.get_string (PICTURE_URI));

        if (!source.query_exists ()) {
            debug ("Wallpaper path is invalid");
            display_manager_accounts_service.background_file = "";
            return;
        }

        var wallpaper_name = "wallpaper";

        var greeter_data_dir = Environment.get_variable ("XDG_GREETER_DATA_DIR") ?? Path.build_filename ("/var/lib/lightdm-data", Environment.get_user_name ());
        var folder = File.new_for_path (greeter_data_dir);
        var dest = folder.get_child (wallpaper_name);

        try {
            if (!folder.query_exists ()) {
                folder.make_directory_with_parents ();
            }

            if (FileUtils.test (dest.get_path (), IS_DIR)) {
                debug ("Migrating to new wallpaper directory");
                remove_directory (dest);
            }

            source.copy (dest, OVERWRITE | ALL_METADATA);
            // Ensure wallpaper is readable by greeter user (owner rw, others r)
            FileUtils.chmod (dest.get_path (), 0604);

            display_manager_accounts_service.background_file = dest.get_path ();
        } catch (IOError.IS_DIRECTORY e) {
            critical ("Migration failed %s", e.message);
            display_manager_accounts_service.background_file = "";
        } catch (Error e) {
            warning (e.message);
            display_manager_accounts_service.background_file = "";
        }
    }

    private void remove_directory (File directory) {
        try {
            var enumerator = directory.enumerate_children (
                FileAttribute.STANDARD_NAME, NOFOLLOW_SYMLINKS
            );

            FileInfo file_info;
            while ((file_info = enumerator.next_file ()) != null) {
                var file = directory.get_child (file_info.get_name ());
                if (file_info.get_file_type () == DIRECTORY) {
                    remove_directory (file);
                }
                file.delete ();
            }
            directory.delete ();
        } catch (Error e) {
            critical ("Couldn't remove directory %s: %s", directory.get_path (), e.message);
        }
    }
}

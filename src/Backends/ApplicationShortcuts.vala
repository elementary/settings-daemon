/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 */

public class SettingsDaemon.Backends.ApplicationShortcuts : Object {
    private enum ActionType {
        DESKTOP_FILE,
        COMMAND_LINE
    }

    private struct Parsed {
        ActionType type;
        string target;
        GLib.HashTable<string, Variant> parameters;
        string[] keybindings;
    }

    private struct ActionInfo {
        ActionType type;
        string target;
        GLib.HashTable<string, Variant> parameters;
    }

    private GLib.Settings application_settings;
    private ShellKeyGrabber? key_grabber = null;
    private DesktopIntegration? desktop_integration = null;
    private ulong key_grabber_id = 0;
    private GLib.HashTable<uint, ActionInfo?> saved_action_ids;

    construct {
        application_settings = new GLib.Settings ("io.elementary.settings-daemon.applications");
        saved_action_ids = new GLib.HashTable<uint, ActionInfo?> (null, null);

        migrate_gsd_shortcuts.begin ();

        application_settings.changed.connect (() => {
            if (key_grabber != null) {
                try {
                    key_grabber.ungrab_accelerators (saved_action_ids.get_keys_as_array ());
                } catch (Error e) {
                    critical ("Couldn't ungrab accelerators: %s", e.message);
                }

                if (key_grabber_id != 0) {
                    key_grabber.disconnect (key_grabber_id);
                    key_grabber_id = 0;
                }

                setup_grabs ();
            }
        });

        Bus.watch_name (BusType.SESSION,
            "org.gnome.Shell",
            BusNameWatcherFlags.NONE,
            (connection) => {
                connection.get_proxy.begin<ShellKeyGrabber> (
                    "org.gnome.Shell", "/org/gnome/Shell", NONE, null,
                    (obj, res) => {
                        try {
                            key_grabber = ((GLib.DBusConnection) obj).get_proxy.end<ShellKeyGrabber> (res);
                            setup_grabs ();
                        } catch (Error e) {
                            critical (e.message);
                            key_grabber = null;
                        }
                    }
                );
            },
            () => {
                if (key_grabber_id != 0) {
                    key_grabber.disconnect (key_grabber_id);
                    key_grabber_id = 0;
                }

                key_grabber = null;
                critical ("Lost connection to org.gnome.Shell");
            }
        );

        Bus.watch_name (
            BusType.SESSION,
            "org.pantheon.gala",
            BusNameWatcherFlags.NONE,
            (connection) => {
                connection.get_proxy.begin<DesktopIntegration> (
                    "org.pantheon.gala", "/org/pantheon/gala/DesktopInterface", NONE, null,
                    (obj, res) => {
                        try {
                            desktop_integration = ((GLib.DBusConnection) obj).get_proxy.end<DesktopIntegration> (res);
                        } catch (Error e) {
                            critical (e.message);
                            desktop_integration = null;
                        }
                    }
                );
            },
            () => {
                desktop_integration = null;
                critical ("Lost connection to org.pantheon.gala.DesktopIntegration");
            }
        );
    }

    private async void migrate_gsd_shortcuts () {
        unowned var settings_schema = GLib.SettingsSchemaSource.get_default ();
        if (settings_schema.lookup ("org.gnome.settings-daemon.plugins.media-keys", false) != null) {
            var value = (Parsed[]) application_settings.get_value ("application-shortcuts");

            var gsd_settings = new GLib.Settings ("org.gnome.settings-daemon.plugins.media-keys");
            var enabled_keybindings = gsd_settings.get_strv ("custom-keybindings");

            for (var i = 0; i < enabled_keybindings.length; i++) {
                var settings = new GLib.Settings.with_path ("org.gnome.settings-daemon.plugins.media-keys.custom-keybinding", enabled_keybindings[i]);
                Parsed new_shortcut = {
                    ActionType.COMMAND_LINE,
                    settings.get_string ("command"),
                    new GLib.HashTable<string, Variant> (null, null),
                    { settings.get_string ("binding") }
                };
                value += new_shortcut;
            }

            application_settings.set_value ("application-shortcuts", value);
            gsd_settings.set_strv ("custom-keybindings", {});
        }
    }

    private void setup_grabs () requires (key_grabber != null) {
        Accelerator[] accelerators = {};

        var parsed_value = (Parsed[]) application_settings.get_value ("application-shortcuts");
        for (var i = 0; i < parsed_value.length; i++) {
            var keybindings = parsed_value[i].keybindings;
            for (var j = 0; j < keybindings.length; j++) {
                accelerators += Accelerator () {
                    name = keybindings[j],
                    mode_flags = ActionMode.NONE,
                    grab_flags = Meta.KeyBindingFlags.NONE
                };
            }
        }

        uint[] action_ids;
        try {
            action_ids = key_grabber.grab_accelerators (accelerators);
        } catch (Error e) {
            critical (e.message);
            return;
        }

        for (int i = 0; i < action_ids.length; i++) {
            var parsed_value_i = parsed_value[i];
            saved_action_ids[action_ids[i]] = { parsed_value_i.type, parsed_value_i.target, parsed_value_i.parameters };
        }

        key_grabber_id = key_grabber.accelerator_activated.connect (on_accelerator_activated);
    }

    private void on_accelerator_activated (uint action, GLib.HashTable<string, GLib.Variant> parameters_dict) {
        var action_info = saved_action_ids[action];
        if (action_info == null) {
            return;
        }

        var context = Gdk.Display.get_default ().get_app_launch_context ();
        context.set_timestamp ("timestamp" in parameters_dict ? (uint32) parameters_dict["timestamp"] : Gdk.CURRENT_TIME);

        var action_parameters = action_info.parameters;

        switch (action_info.type) {
            case DESKTOP_FILE:
                var desktop_file_name = action_info.target;

                DesktopIntegration.RunningApplication[] apps = {};
                if (desktop_integration != null) {
                    try {
                        apps = desktop_integration.get_running_applications ();
                    } catch (Error e) {
                        warning (e.message);
                    }
                }

                var already_launched = false;
                for (var i = 0; i < apps.length; i++) {
                    if (apps[i].app_id == desktop_file_name) {
                        already_launched = true;
                        break;
                    }
                }

                if ("action" in action_parameters) {
                    unowned var action_name = action_parameters["action"].get_string ();
                    new DesktopAppInfo (desktop_file_name).launch_action (action_name, context);
                } else if (!already_launched || desktop_integration == null) {
                    launch_app (desktop_file_name, context);
                } else {
                    try {
                        var found_window = false;
                        var windows = desktop_integration.get_windows ();
                        for (var i = 0; i < windows.length; i++) {
                            if (windows[i].properties["app-id"].get_string () == desktop_file_name) {
                                found_window = true;
                                desktop_integration.focus_window (windows[i].uid);
                                break;
                            }
                        }

                        if (!found_window) {
                            launch_app (desktop_file_name, context);
                        }
                    } catch (Error e) {
                        warning (e.message);
                        launch_app (desktop_file_name, context);
                    }
                }
                break;

            case COMMAND_LINE:
                var commandline = action_info.target;
                var flags = GLib.AppInfoCreateFlags.NONE;
                if ("needs-terminal" in action_parameters && action_parameters["needs-terminal"].get_boolean ()) {
                    flags = GLib.AppInfoCreateFlags.NEEDS_TERMINAL;
                }

                try {
                    AppInfo.create_from_commandline (commandline, null, flags).launch (null, context);
                } catch (Error e) {
                    warning ("Couldn't launch %s: %s", commandline, e.message);
                }
                break;
        }
    }

    private void launch_app (string desktop_file_name, Gdk.AppLaunchContext context) {
        try {
            new DesktopAppInfo (desktop_file_name).launch (null, context);
        } catch (Error e) {
            warning ("Couldn't launch %s: %s", desktop_file_name, e.message);
        }
    }
}

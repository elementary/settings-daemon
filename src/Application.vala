/*
* Copyright 2020 elementary, Inc. (https://elementary.io)
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

public class SettingsDaemon.Application : GLib.Application {
    public const OptionEntry[] OPTIONS = {
        { "version", 'v', 0, OptionArg.NONE, out show_version, "Display the version", null},
        { null }
    };

    public static bool show_version;

    private Application () {}

    private SessionClient? session_client;

    private AccountsService? accounts_service;

    private PantheonShell.Pantheon.AccountsService pantheon_accounts_service;

    private Backends.KeyboardSettings keyboard_settings;

    private Backends.MouseSettings mouse_settings;

    private Backends.PrefersColorSchemeSettings prefers_color_scheme_settings;

    private Backends.Housekeeping housekeeping;

    construct {
        application_id = Build.PROJECT_NAME;

        add_main_option_entries (OPTIONS);

        housekeeping = new Backends.Housekeeping ();

        var check_firmware_updates_action = new SimpleAction ("check-firmware-updates", null);
        check_firmware_updates_action.activate.connect (() => {
            var fwupd_client = new Fwupd.Client ();
            var num_updates = 0;
            try {
                var devices = fwupd_client.get_devices ();
                for (int i = 0; i < devices.length; i++) {
                    var device = devices[i];
                    if (device.has_flag (Fwupd.DEVICE_FLAG_UPDATABLE)) {
                        Fwupd.Release? release = null;
                        try {
                            var upgrades = fwupd_client.get_upgrades (device.get_id ());

                            if (upgrades != null) {
                                release = upgrades[0];
                            }
                        } catch (Error e) {
                            warning (e.message);
                        }

                        if (release != null && device.get_version () != release.get_version ()) {
                            num_updates++;
                        }
                    }
                }
            } catch (Error e) {
                warning (e.message);
            }

            if (num_updates != 0U) {
                string title = ngettext ("Firmware Update Available", "Firmware Updates Available", num_updates);
                string body = ngettext ("%u update is available for your hardware", "%u updates are available for your hardware", num_updates).printf (num_updates);

                var notification = new Notification (title);
                notification.set_body (body);
                notification.set_icon (new ThemedIcon ("application-x-firmware"));
                notification.set_default_action ("app.show-firmware-updates");

                send_notification ("io.elementary.settings-daemon.firmware.updates", notification);
            } else {
                withdraw_notification ("io.elementary.settings-daemon.firmware.updates");
            }
        });

        var show_firmware_updates_action = new SimpleAction ("show-firmware-updates", null);
        show_firmware_updates_action.activate.connect (() => {
            try {
                Gtk.show_uri_on_window (null, "settings://about/firmware", Gdk.CURRENT_TIME);
            } catch (Error e) {
                critical (e.message);
            }
        });

        add_action (check_firmware_updates_action);
        add_action (show_firmware_updates_action);
    }

    public override int handle_local_options (VariantDict options) {
        if (show_version) {
            stdout.printf ("%s\n", Build.VERSION);
            return 0;
        }

        return -1;
    }

    public override void activate () {
        register_with_session_manager.begin ();
        setup_accountsservice.begin ();

        hold ();
    }

    private async bool register_with_session_manager () {
        session_client = yield register_with_session (Build.PROJECT_NAME);

        session_client.query_end_session.connect (() => end_session (false));
        session_client.end_session.connect (() => end_session (false));
        session_client.stop.connect (() => end_session (true));

        return true;
    }

    private async void setup_accountsservice () {
        try {
            var act_service = yield GLib.Bus.get_proxy<FDO.Accounts> (GLib.BusType.SYSTEM,
                                                                      "org.freedesktop.Accounts",
                                                                      "/org/freedesktop/Accounts");
            var user_path = act_service.find_user_by_name (GLib.Environment.get_user_name ());

            accounts_service = yield GLib.Bus.get_proxy (GLib.BusType.SYSTEM,
                                                         "org.freedesktop.Accounts",
                                                         user_path,
                                                         GLib.DBusProxyFlags.GET_INVALIDATED_PROPERTIES);
        } catch (Error e) {
            warning ("Could not connect to AccountsService. Settings will not be synced to the greeter");
        }

        if (accounts_service != null) {
            keyboard_settings = new Backends.KeyboardSettings (accounts_service);
            mouse_settings = new Backends.MouseSettings (accounts_service);
        }

        try {
            var act_service = yield GLib.Bus.get_proxy<FDO.Accounts> (GLib.BusType.SYSTEM,
                                                                      "org.freedesktop.Accounts",
                                                                      "/org/freedesktop/Accounts");
            var user_path = act_service.find_user_by_name (GLib.Environment.get_user_name ());

            pantheon_accounts_service = yield GLib.Bus.get_proxy (GLib.BusType.SYSTEM,
                                                                  "org.freedesktop.Accounts",
                                                                  user_path,
                                                                  GLib.DBusProxyFlags.GET_INVALIDATED_PROPERTIES);
        } catch (Error e) {
            warning ("Unable to get AccountsService proxy, color scheme preference may be incorrect");
        }

        if (pantheon_accounts_service != null) {
            prefers_color_scheme_settings = new Backends.PrefersColorSchemeSettings (pantheon_accounts_service);
        }
    }

    void end_session (bool quit) {
        if (quit) {
            release ();
            return;
        }

        try {
            session_client.end_session_response (true, "");
        } catch (Error e) {
            warning ("Unable to respond to session manager: %s", e.message);
        }
    }

    public static int main (string[] args) {
        GLib.Intl.setlocale (LocaleCategory.ALL, "");
        GLib.Intl.bindtextdomain (Build.GETTEXT_PACKAGE, Build.LOCALEDIR);
        GLib.Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
        GLib.Intl.textdomain (Build.GETTEXT_PACKAGE);

        var application = new Application ();
        return application.run (args);
    }
}

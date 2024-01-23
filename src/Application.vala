/*
 * Copyright 2020-2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public sealed class SettingsDaemon.Application : Gtk.Application {
    public const string ACTION_PREFIX = "app.";
    public const string SHOW_UPDATES_ACTION = "show-updates";

    private AccountsService accounts_service;
    private Pantheon.AccountsService pantheon_service;
    private DisplayManager.AccountsService display_manager_service;

    private Backends.KeyboardSettings keyboard_settings;
    private Backends.MouseSettings mouse_settings;

    private Backends.InterfaceSettings interface_settings;
    private Backends.NightLightSettings night_light_settings;
    private Backends.PrefersColorSchemeSettings prefers_color_scheme_settings;

    private Backends.Housekeeping housekeeping;

    private const string FDO_ACCOUNTS_NAME = "org.freedesktop.Accounts";
    private const string FDO_ACCOUNTS_PATH = "/org/freedesktop/Accounts";

    public Application () {
        Object (
            application_id: Build.PROJECT_NAME,
            flags: GLib.ApplicationFlags.IS_SERVICE | GLib.ApplicationFlags.ALLOW_REPLACEMENT,
            register_session: true
        );
    }

    construct {
        GLib.Intl.setlocale (ALL, "");
        GLib.Intl.bindtextdomain (Build.GETTEXT_PACKAGE, Build.LOCALEDIR);
        GLib.Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
        GLib.Intl.textdomain (Build.GETTEXT_PACKAGE);

        add_main_option ("version", 'v', NONE, NONE, "Display the version", null);
    }

    protected override int handle_local_options (VariantDict options) {
        if ("version" in options) {
            stdout.printf ("%s\n", Build.VERSION);
            return 0;
        }

        return -1;
    }

    protected override void startup () {
        query_end.connect (() => release ());
        base.startup ();

        housekeeping = new Backends.Housekeeping ();

        var check_firmware_updates_action = new GLib.SimpleAction ("check-firmware-updates", null);
        check_firmware_updates_action.activate.connect (check_firmware_updates);
        add_action (check_firmware_updates_action);

        var show_firmware_updates_action = new GLib.SimpleAction ("show-firmware-updates", null);
        show_firmware_updates_action.activate.connect (show_firmware_updates);
        add_action (show_firmware_updates_action);

        var show_updates_action = new GLib.SimpleAction (SHOW_UPDATES_ACTION, null);
        show_updates_action.activate.connect (() => {
            GLib.AppInfo.launch_default_for_uri_async.begin ("settings://about/os", null);
        });
        add_action (show_updates_action);

        setup_accounts_services.begin ();
        hold ();
    }

    protected override bool dbus_register (DBusConnection connection, string object_path) throws Error {
        base.dbus_register (connection, object_path);

        connection.register_object (object_path, new Backends.SystemUpdate ());

        return true;
    }

    private async void setup_accounts_services () {
        unowned GLib.DBusConnection connection;
        string path;

        try {
            connection = yield GLib.Bus.get (SYSTEM);

            var reply = yield connection.call (
                FDO_ACCOUNTS_NAME, FDO_ACCOUNTS_PATH,
                FDO_ACCOUNTS_NAME, "FindUserByName",
                new GLib.Variant.tuple ({ new GLib.Variant.string (GLib.Environment.get_user_name ()) }),
                new VariantType ("(o)"),
                NONE,
                -1
            );
            reply.get_child (0, "o", out path);

            accounts_service = yield connection.get_proxy (FDO_ACCOUNTS_NAME, path, GET_INVALIDATED_PROPERTIES);
            keyboard_settings = new Backends.KeyboardSettings (accounts_service);
            mouse_settings = new Backends.MouseSettings (accounts_service);
            night_light_settings = new Backends.NightLightSettings (accounts_service);
        } catch {
            warning ("Could not connect to AccountsService. Settings will not be synced");
            return;
        }

        try {
            display_manager_service = yield connection.get_proxy (FDO_ACCOUNTS_NAME, path, GET_INVALIDATED_PROPERTIES);
            interface_settings = new Backends.InterfaceSettings (accounts_service, display_manager_service);
        } catch {
            warning ("Unable to get LightDM's AccountsService proxy, background file might be incorrect");
        }

        try {
            pantheon_service = yield connection.get_proxy (FDO_ACCOUNTS_NAME, path, GET_INVALIDATED_PROPERTIES);
            prefers_color_scheme_settings = new Backends.PrefersColorSchemeSettings (pantheon_service);
        } catch {
            warning ("Unable to get pantheon's AccountsService proxy, color scheme preference may be incorrect");
        }
    }

    private void check_firmware_updates () {
        var client = new Fwupd.Client ();
        var updates = 0;

        try {
            var devices = client.get_devices ();

            foreach (unowned var device in devices) {
                if (!device.has_flag (Fwupd.DEVICE_FLAG_UPDATABLE)) {
                    continue;
                }

                Fwupd.Release? release = null;

                try {
                    var upgrades = client.get_upgrades (device.get_id ());
                    if (upgrades != null) {
                        release = upgrades[0];
                    }
                } catch (Error e) {
                    warning (e.message);
                    continue;
                }

                if (release != null && device.get_version () != release.get_version ()) {
                    updates++;
                }
            }
        } catch (Error e) {
            warning (e.message);
        }

        if (updates != 0) {
            var title = ngettext ("Firmware Update Available", "Firmware Updates Available", updates);
            var body = ngettext (
                "%u update is available for your hardware",
                "%u updates are available for your hardware",
                updates
            );

            var notification = new Notification (title);
            notification.set_body (body.printf (updates));
            notification.set_icon (new ThemedIcon ("application-x-firmware"));
            notification.set_default_action ("app.show-firmware-updates");

            send_notification ("firmware.updates", notification);
        } else {
            withdraw_notification ("firmware.updates");
        }
    }

    private void show_firmware_updates () {
        var context = Gdk.Display.get_default ().get_app_launch_context ();

        GLib.AppInfo.launch_default_for_uri_async.begin ("settings://about/firmware", context, null, (obj, res) => {
            try {
                GLib.AppInfo.launch_default_for_uri_async.end (res);
            } catch (GLib.Error e) {
                critical (e.message);
            }
        });
    }

    public static int main (string[] args) {
        return new SettingsDaemon.Application ().run (args);
    }
}

/*
 * Copyright 2022 elementary, Inc. (https://elementary.io)
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

public class SettingsDaemon.Backends.Firmware : GLib.Object {
    private GLib.Settings firmware_settings;

    private GLib.DateTime last_firmware_check = null;

    private const int SECONDS_BETWEEN_REFRESHES = 60 * 60 * 24;

    public uint firmware_updates_number { get; private set; default = 0U; }

    private AsyncMutex update_notification_mutex = new AsyncMutex ();
    private AsyncMutex firmware_update_notification_mutex = new AsyncMutex ();

    public GLib.Application application { get; construct; }

    public Firmware (GLib.Application application) {
        Object (
            application: application
        );
    }

    construct {
        firmware_settings = new GLib.Settings ("io.elementary.settings-daemon.firmware");

        last_firmware_check = new DateTime.from_unix_utc (firmware_settings.get_int64 ("last-refresh-time"));

        check_seconds_between_refreshes ();

        Timeout.add_seconds (SECONDS_BETWEEN_REFRESHES, check_seconds_between_refreshes);
    }

    private bool check_seconds_between_refreshes () {
        /* One cache update a day, keeps the doctor away! */
        var seconds_since_last_refresh = new DateTime.now_utc ().difference (last_firmware_check) / GLib.TimeSpan.SECOND;
        if (seconds_since_last_refresh >= SECONDS_BETWEEN_REFRESHES) {
            last_firmware_check = new DateTime.now_utc ();
            firmware_settings.set_int64 ("last-refresh-time", last_firmware_check.to_unix ());

            refresh_firmware_updates.begin ();
        }

        return Source.CONTINUE;
    }

    private async void refresh_firmware_updates () {
        yield firmware_update_notification_mutex.lock ();

        bool was_empty = firmware_updates_number == 0U;

        var fwupd_client = new Fwupd.Client ();
        var num_updates = 0;
        try {
            var devices = yield FirmwareClient.get_devices (fwupd_client);
            for (int i = 0; i < devices.length; i++) {
                var device = devices[i];
                if (device.has_flag (Fwupd.DEVICE_FLAG_UPDATABLE)) {
                    Fwupd.Release? release = null;
                    try {
                        var upgrades = yield FirmwareClient.get_upgrades (fwupd_client, device.get_id ());

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

        if (was_empty && num_updates != 0U) {
            string title = ngettext ("Firmware Update Available", "Firmware Updates Available", num_updates);
            string body = ngettext ("%u update is available for your hardware", "%u updates are available for your hardware", num_updates).printf (num_updates);

            var notification = new Notification (title);
            notification.set_body (body);
            notification.set_icon (new ThemedIcon ("application-x-firmware"));
            notification.set_default_action ("app.show-firmware-updates");

            application.send_notification ("io.elementary.settings-daemon.firmware.updates", notification);
        } else {
            application.withdraw_notification ("io.elementary.settings-daemon.firmware.updates");
        }

        update_notification_mutex.unlock ();
    }
}

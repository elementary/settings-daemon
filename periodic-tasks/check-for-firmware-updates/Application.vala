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

public class CheckForFirmwareUpdates.Application : GLib.Application {
    private Application () {}

    public uint firmware_updates_number { get; private set; default = 0U; }

    construct {
        application_id = Build.PROJECT_NAME + ".check-for-firmware-updates";
    }

    public override void activate () {
        bool was_empty = firmware_updates_number == 0U;

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

        if (was_empty && num_updates != 0U) {
            string title = ngettext ("Firmware Update Available", "Firmware Updates Available", num_updates);
            string body = ngettext ("%u update is available for your hardware", "%u updates are available for your hardware", num_updates).printf (num_updates);

            var notification = new Notification (title);
            notification.set_body (body);
            notification.set_icon (new ThemedIcon ("application-x-firmware"));
            notification.set_default_action ("io.elementary.settings-daemon.show-firmware-updates");

            send_notification ("io.elementary.settings-daemon.firmware.updates", notification);
        } else {
            withdraw_notification ("io.elementary.settings-daemon.firmware.updates");
        }
    }

    public static int main (string[] args) {
        var application = new Application ();
        return application.run (args);
    }
}

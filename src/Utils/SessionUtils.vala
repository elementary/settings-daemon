/*
 * Copyright 2024 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace SettingsDaemon.Utils {
    public static bool is_running_in_demo_mode () {
        var proc_cmdline = File.new_for_path ("/proc/cmdline");
        try {
            var @is = proc_cmdline.read ();
            var dis = new DataInputStream (@is);

            var line = dis.read_line ();
            if ("boot=casper" in line || "boot=live" in line || "rd.live.image" in line) {
                return true;
            }
        } catch (Error e) {
            critical ("Couldn't detect if running in Demo Mode: %s", e.message);
        }

        return false;
    }
}

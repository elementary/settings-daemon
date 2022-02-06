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
 * Authored by: Marius Meisenzahl <mariusmeisenzahl@gmail.com>
 */

[DBus (name = "io.elementary.SystemUpgrade")]
public class SettingsDaemon.Backends.SystemUpgrade : GLib.Object {
    public bool system_upgrade_available {
        get {
            return true;
        }
    }

    public signal void system_upgrade_progress (int percentage);

    public signal void system_upgrade_finished ();

    public signal void system_upgrade_failed (string text);

    public signal void system_upgrade_cancelled ();

    public void start_upgrade () throws Error {
        upgrade_async.begin ();
    }

    public void cancel () throws Error {
        cancellable.cancel ();
    }

    private async void upgrade_async () {
        if (cancellable.is_cancelled ()) {
            cancellable.reset ();
        }

        Inhibitor.get_instance ().inhibit ();

        Pk.Results? results = null;

        try {
            debug ("Refresh cache");
            results = yield task.refresh_cache_async (true, cancellable, (t, p) => { });

            debug ("Get repositories");
            results = yield task.get_repo_list_async (Pk.Bitfield.from_enums (Pk.Filter.NONE), cancellable, (p, t) => { });

            var repo_files = new Array<string> ();
            var repos = results.get_repo_detail_array ();
            for (int i = 0; i < repos.length; i++) {
                var repo = repos[i];

                // TODO: check for ppas

                var parts = repo.repo_id.split (":", 2);
                var f = parts[0];

                if (!FileUtils.test (f, FileTest.EXISTS)) {
                    continue;
                }

                bool found = false;
                for (int j = 0; j < repo_files.length; j++) {
                    if (repo_files.index (j) == f) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    repo_files.append_val (f);
                }
            }

            var helper = new Utils.SystemUpgradeHelper ();

            debug ("Update repositories");
            for (int i = 0; i < repo_files.length; i++) {
                var repository_file = repo_files.index (i);
                debug ("    %s", repository_file);

                if (!helper.update_third_party_repository ("focal", "jammy", repository_file)) {
                    throw new Error (0, 0, "Could not update repository: %s\n", repository_file);
                }
            }

            if (!helper.install_files ("jammy")) {
                throw new Error (0, 0, "Could not install files\n");
            }

            debug ("Refresh cache");
            results = yield task.refresh_cache_async (true, cancellable, (p, t) => { });

            if (results == null) {
                throw new Error (0, 0, "Could not refresh cache");
            }

            debug ("Get updates");
            results = yield task.get_updates_async (Pk.Bitfield.from_enums (Pk.Filter.NEWEST), cancellable, (t, p) => { });

            if (results == null) {
                throw new Error (0, 0, "Could not get updates");
            }

            var sack = results.get_package_sack ();
            sack.remove_by_filter (update_system_filter_helper);
            var package_ids = sack.get_ids ();

            task.only_download = true;

            debug ("Download packages");
            var status = Pk.Status.UNKNOWN;
            int percentage = -1;
            results = yield task.update_packages_async (package_ids, cancellable, ((p, t) => {
                if (t == Pk.ProgressType.STATUS) {
                    status = p.get_status ();
                }

                int new_percentage = percentage;
                if (t == Pk.ProgressType.PERCENTAGE && status == Pk.Status.DOWNLOAD) {
                    new_percentage = p.percentage;
                }

                if (status == Pk.Status.FINISHED) {
                    new_percentage = 100;
                }

                if (new_percentage != percentage) {
                    percentage = new_percentage;
                    system_upgrade_progress (percentage);
                }
            }));

            if (results == null) {
                throw new Error (0, 0, "Could not download packages");
            }

            debug ("Set PackageKit reboot action");
            Pk.offline_trigger (Pk.OfflineAction.REBOOT, cancellable);

            debug ("Ready to reboot");

            system_upgrade_finished ();
        } catch (Error e) {
            warning ("Upgrade failed: %s", e.message);

            system_upgrade_failed (e.message);
        }

        Inhibitor.get_instance ().uninhibit ();
    }

    construct {
        task = new Pk.Task ();
        cancellable = new Cancellable ();

        cancellable.cancelled.connect (() => { system_upgrade_cancelled (); });
    }

    private static Pk.Task task;
    private static Cancellable cancellable;

    private bool update_system_filter_helper (Pk.Package package) {
        var info = package.get_info ();
        return (info != Pk.Info.OBSOLETING && info != Pk.Info.REMOVING);
    }
}

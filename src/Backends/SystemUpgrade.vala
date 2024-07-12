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

        if (is_system_upgrade_running) {
            is_system_upgrade_running = false;
        }
    }

    private async void upgrade_async () {
        if (is_system_upgrade_running) {
            return;
        }

        if (cancellable.is_cancelled ()) {
            cancellable.reset ();
        }

        is_system_upgrade_running = true;

        Inhibitor.get_instance ().inhibit ();

        
        try {
            info ("Refresh cache");
            Pk.Results? results = null;
            results = yield task.refresh_cache_async (true, cancellable, (t, p) => { });
            info ("Successfully refreshed cache");

            if (cancellable.is_cancelled ()) {
                Inhibitor.get_instance ().uninhibit ();
                return;
            }

            //  yield update_repositories ();

            if (cancellable.is_cancelled ()) {
                Inhibitor.get_instance ().uninhibit ();
                return;
            }

            yield remove_old_settings ();

            if (cancellable.is_cancelled ()) {
                Inhibitor.get_instance ().uninhibit ();
                return;
            }

            yield install_systemd_resolved ();

            if (cancellable.is_cancelled ()) {
                Inhibitor.get_instance ().uninhibit ();
                return;
            }

            yield do_upgrade ();

            if (cancellable.is_cancelled ()) {
                Inhibitor.get_instance ().uninhibit ();
                return;
            }

            yield install_new_settings ();

            if (cancellable.is_cancelled ()) {
                Inhibitor.get_instance ().uninhibit ();
                return;
            }

            install_network_manager_config ();

            info ("Set PackageKit reboot action");
            Pk.offline_trigger (Pk.OfflineAction.REBOOT, cancellable);

            if (cancellable.is_cancelled ()) {
                Inhibitor.get_instance ().uninhibit ();
                return;
            }

            info ("Ready to reboot");

            system_upgrade_finished ();
        } catch (Error e) {
            warning ("Upgrade failed: %s", e.message);

            system_upgrade_failed (e.message);
        }

        is_system_upgrade_running = false;

        Inhibitor.get_instance ().uninhibit ();
    }

    private async void update_repositories () throws GLib.Error{
        info ("Get repositories");
        var results = yield task.get_repo_list_async (Pk.Bitfield.from_enums (Pk.Filter.NONE), cancellable, (p, t) => {});

        if (cancellable.is_cancelled ()) {
            Inhibitor.get_instance ().uninhibit ();
            return;
        }

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

        info ("Update repositories");
        for (int i = 0; i < repo_files.length; i++) {
            var repository_file = repo_files.index (i);
            info ("    %s", repository_file);

            if (!helper.update_third_party_repository ("jammy", "noble", repository_file)) {
                throw new Error (0, 0, "Could not update repository: %s\n", repository_file);
            }
        }

        info ("Refresh cache");
        results = yield task.refresh_cache_async (true, cancellable, (p, t) => { });
        if (results == null) {
            throw new Error (0, 0, "Could not refresh cache");
        }
    }

    private async void remove_old_settings () throws GLib.Error {
        info ("Removing old (Gtk3) Settings");
        var results = task.search_names_sync (Pk.Bitfield.from_enums (Pk.Filter.INSTALLED), {"switchboard"}, cancellable, () => {});

        var sack = results.get_package_sack ();
        sack.remove_by_filter (update_system_filter_helper);
        var package_ids = sack.get_ids ();

        string[] packages_to_remove = {};
        foreach (unowned var id in package_ids) {
            var split = id.split (";");
            if (split.length >= 1 && (split[0] == "switchboard" || split[0].contains ("switchboard-plug"))) {
                packages_to_remove += id;
                break;
            }
        }


        if (packages_to_remove.length > 0) {
            info (string.joinv ("    ", packages_to_remove));
            yield task.remove_packages_async (packages_to_remove, true, true, cancellable, () => {});
        }

        info ("Successfully removed old settings");
    }

    private async void install_systemd_resolved () throws GLib.Error {
        var results = task.search_names_sync (Pk.Bitfield.from_enums (Pk.Filter.NONE), {"systemd-resolved"}, cancellable, () => {});

        var package_ids = results.get_package_sack ().get_ids ();

        string? systemd_resolved_package = null;
        foreach (unowned var id in package_ids) {
            var split = id.split (";");
            if (split.length >= 1 && split[0] == "systemd-resolved") {
                systemd_resolved_package = id;
                break;
            }
        }

        yield task.install_packages_async ({systemd_resolved_package}, cancellable, () => {});
    }

    private async void do_upgrade () throws GLib.Error {
        info ("Get updates");
        var results = yield task.get_updates_async (Pk.Bitfield.from_enums (Pk.Filter.NEWEST), cancellable, (t, p) => { });

        if (cancellable.is_cancelled ()) {
            Inhibitor.get_instance ().uninhibit ();
            return;
        }

        if (results == null) {
            throw new Error (0, 0, "Could not get updates");
        }

        var sack = results.get_package_sack ();
        sack.remove_by_filter (update_system_filter_helper);
        var package_ids = sack.get_ids ();

        info ("Download packages");
        var status = Pk.Status.UNKNOWN;
        int percentage = -1;
        results = yield task.update_packages_async (package_ids, cancellable, (p, t) => {
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
        });

        if (results == null) {
            throw new Error (0, 0, "Could not download packages");
        }

        info ("Successfully downloaded packages");
    }

    private async void install_new_settings () throws GLib.Error {
        info ("Installing new (Gtk4) Settings");

        var results = task.search_names_sync (Pk.Bitfield.from_enums (Pk.Filter.INSTALLED), {"io.elementary.settings"}, cancellable, () => {});

        yield task.install_packages_async (results.get_package_sack ().get_ids (), cancellable, () => {});

        info ("Successfully installed new Settings");
    }

    private void install_network_manager_config () throws GLib.Error {
        info ("Installing NetworkManager config");
        if (!helper.install_network_manager_config ()) {
            throw new Error (0, 0, "Could not install NetworkManager config");
        }
        info ("Successfully installed NetworkManager config");
    }

    construct {
        task = new Pk.Task () {
            only_download = true,
            simulate = true
        };
        cancellable = new Cancellable ();
        helper = new Utils.SystemUpgradeHelper ();

        cancellable.cancelled.connect (() => { system_upgrade_cancelled (); });
    }

    private static Pk.Task task;
    private static Cancellable cancellable;
    private static Utils.SystemUpgradeHelper helper;

    private bool is_system_upgrade_running = false;

    private bool update_system_filter_helper (Pk.Package package) {
        var info = package.get_info ();
        return (info != Pk.Info.OBSOLETING && info != Pk.Info.REMOVING);
    }
}

/*
 * Copyright 2026 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Utils.SysupdateTarget : Object {
    public enum UpdateVersion {
        NEWEST,
        CURRENT,
    }

    public delegate void ProgressCallback (string message, uint percentage);

    public string path { get; construct; }

    private Sysupdate.Target? target;

    public SysupdateTarget (string path) {
        Object (path: path);
    }

    private async void ensure_connected () throws Error {
        if (target != null) {
            return;
        }

        target = yield Bus.get_proxy (SYSTEM, Sysupdate.BUS_NAME, path, NONE, null);
    }

    public async string? check_new () throws Error {
        yield ensure_connected ();

        var new_version = yield target.check_new ();

        if (new_version == "") {
            /* Docs say "" means no new version is available so make it clearer by returning null */
            return null;
        }

        return new_version;
    }

    /**
     * Runs an update. This is both used to actually update the system to a newer version
     * but also to apply newly selected or deselected features.
     * You can specify what version you want to use with {@link version}.
     */
    public async void update (UpdateVersion version, Cancellable cancellable, ProgressCallback progress_callback) throws Error {
        progress_callback (_("Preparing update"), 0);

        yield ensure_connected ();

        /* "" means newest available so we use it when version is UpdateVersion.NEWEST */
        string version_string = "";

        if (version == CURRENT) {
            version_string = yield target.get_version ();
        }

        var manager = yield new SysupdateJobManager (cancellable);

        progress_callback (_("Starting update"), 0);

        string used_version;
        uint64 job_id;
        ObjectPath job_path;
        yield target.update (version_string, 0, out used_version, out job_id, out job_path);

        var job = yield new SysupdateJob (job_path, cancellable, progress_callback);

        yield manager.wait_for_job (job);
    }

    /**
     * Checks if there is a new version already downloaded and installed but not booted into.
     * Most commonly this means we ran update but haven't rebooted into the new version yet.
     */
    public async bool has_newer_unapplied_version () throws Error {
        yield ensure_connected ();

        var newest_installed_version = yield target.get_version ();
        var booted_version = Environment.get_os_info ("IMAGE_VERSION");

        return newest_installed_version != booted_version;
    }
}

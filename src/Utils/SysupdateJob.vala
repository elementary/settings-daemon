/*
 * Copyright 2026 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Utils.SysupdateJob : Object {
    public ObjectPath path { get; construct; }

    private Cancellable cancellable;
    private unowned SysupdateTarget.ProgressCallback progress_callback;

    private Sysupdate.Job? job;

    /**
     * Starts observing the job at the given path, cancelling it when the cancellable is triggered
     * and calling the progress callback with progress updates.
     */
    public async SysupdateJob (ObjectPath path, Cancellable cancellable, SysupdateTarget.ProgressCallback progress_callback) throws Error {
        Object (path: path);

        this.cancellable = cancellable;
        this.progress_callback = progress_callback;

        job = yield Bus.get_proxy (SYSTEM, Sysupdate.BUS_NAME, path, NONE);
        job.g_properties_changed.connect (on_properties_changed);

        cancellable.cancelled.connect (cancel);

        if (cancellable.is_cancelled ()) {
            /* The user tried to cancel while the job was being started */
            cancel ();
        }
    }

    private void on_properties_changed () requires (job != null) {
        progress_callback (_("Downloading new image"), job.progress);
    }

    private void cancel () requires (job != null) {
        job.cancel.begin ((obj, res) => {
            try {
                job.cancel.end (res);
            } catch (Error e) {
                warning ("Failed to cancel job: %s", e.message);
            }
        });
    }

    internal void notify_completed () {
        job = null;
    }
}

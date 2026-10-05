/*
 * Copyright 2026 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Utils.SysupdateJob : Object {
    public signal void progress_changed (string message, uint progress);

    private Sysupdate.Job job;

    public async SysupdateJob (ObjectPath job_path) throws Error {
        job = yield Bus.get_proxy (SYSTEM, Sysupdate.BUS_NAME, job_path, NONE);
        job.g_properties_changed.connect (on_properties_changed);
    }

    private void on_properties_changed () {
        progress_changed (_("Downloading new image"), job.progress);
    }

    private void cancel () {
        job.cancel.begin ((obj, res) => {
            try {
                job.cancel.end (res);
            } catch (Error e) {
                warning ("Failed to cancel job: %s", e.message);
            }
        });
    }

    public void start_observing (Cancellable cancellable, SysupdateTarget.ProgressCallback progress_callback) {
        cancellable.cancelled.connect (cancel);
        progress_changed.connect (progress_callback);

        if (cancellable.is_cancelled ()) {
            cancel ();
        }
    }

    public void stop_observing (Cancellable cancellable, SysupdateTarget.ProgressCallback progress_callback) {
        cancellable.cancelled.disconnect (cancel);
        progress_changed.disconnect (progress_callback);
    }
}

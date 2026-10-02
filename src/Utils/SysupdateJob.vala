/*
 * Copyright 2026 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Utils.SysupdateJob : Object {
    private Cancellable cancellable;
    private SysupdateTarget.ProgressCallback progress_callback;
    private Sysupdate.Job job;

    /**
     * Starts observing the given job, calling the progress callback with progess
     * and cancelling it if the cancellable is triggered.
     */
    public async SysupdateJob (ObjectPath job_path, Cancellable cancellable, SysupdateTarget.ProgressCallback progress_callback) throws Error {
        this.cancellable = cancellable;
        cancellable.cancelled.connect (cancel_job);

        this.progress_callback = progress_callback;

        this.job = yield Bus.get_proxy (SYSTEM, Sysupdate.BUS_NAME, job_path, NONE, cancellable);
    }

    private async void cancel_job () requires (job != null) {
        try {
            yield job.cancel ();
        } catch (Error e) {
            warning ("Failed to cancel job: %s", e.message);
        }
    }
}

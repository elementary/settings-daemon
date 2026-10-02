/*
 * Copyright 2026 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Utils.SysupdateJobManager : Object {
    private Sysupdate.Manager manager;

    private HashTable<string, int> received_object_paths;

    public async SysupdateJobManager (Cancellable cancellable) throws Error {
        manager = yield Bus.get_proxy (SYSTEM, Sysupdate.BUS_NAME, Sysupdate.Manager.PATH, NONE, cancellable);
        manager.job_removed.connect (on_job_removed);
    }

    construct {
        received_object_paths = new HashTable<string, int> (str_hash, str_equal);
    }

    private void on_job_removed (uint64 finished_job_id, string finished_object_path, int status) {
        received_object_paths[finished_object_path] = status;
    }

    /**
     * Waits for the job to complete or returns immediately if the job has already completed.
     * If the job has failed an error will be thrown.
     * Note that for this to reliably work without races the this has to have been created before
     * the job was started.
     */
    public async void wait_for_job (string object_path) throws Error {
        if (object_path in received_object_paths) {
            check_status (object_path);
            return;
        }

        var signal_id = manager.job_removed.connect ((job_id, job_path) => {
            if (job_path == object_path) {
                wait_for_job.callback ();
            }
        });

        yield;

        manager.disconnect (signal_id);

        check_status (object_path);
    }

    private void check_status (string object_path) throws Error {
        var status = received_object_paths[object_path];
        if (status != 0) {
            throw new IOError.FAILED ("Job failed with status: %d".printf (status));
        }
    }
}

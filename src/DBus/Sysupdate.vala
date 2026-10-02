/*
 * Copyright 2026 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

/**
 * Some of the DBus interfaces here have manually implemented methods.
 * The reason for that is that most of the methods are authenticated via polkit therefore
 * we need to call them with ALLOW_INTERACTIVE_AUTHORIZATION which currently isn't possible
 * via the normal vala way. Therefore all methods that are authenticated via polkit
 * (even if they are by default allowed without privileges e.g. check_new) are manually
 * implemented.
 */
namespace Sysupdate {
    public const string BUS_NAME = "org.freedesktop.sysupdate1";
}

[DBus (name = "org.freedesktop.sysupdate1.Manager")]
private interface Sysupdate.Manager : Object {
    public const string PATH = "/org/freedesktop/sysupdate1";

    public signal void job_removed (uint64 job_id, ObjectPath object_path, int status);
}

[DBus (name = "org.freedesktop.sysupdate1.Target")]
private interface Sysupdate.Target : DBusProxy {
    public const string HOST_PATH = "/org/freedesktop/sysupdate1/target/host";

    public async string check_new () throws Error {
        var result = yield call ("CheckNew", null, ALLOW_INTERACTIVE_AUTHORIZATION, -1);
        return (string) result.get_child_value (0);
    }

    public abstract async string get_version () throws DBusError, IOError;

    public async void update (string new_version, uint64 flags, out string used_version, out uint64 job_id, out ObjectPath job_path) throws Error {
        var parameters = new Variant.tuple ({ new_version, flags });

        var result = yield call ("Update", parameters, ALLOW_INTERACTIVE_AUTHORIZATION, -1);

        used_version = (string) result.get_child_value (0);
        job_id = (uint64) result.get_child_value (1);
        job_path = (ObjectPath) result.get_child_value (2);
    }
}

[DBus (name = "org.freedesktop.sysupdate1.Job")]
private interface Sysupdate.Job : DBusProxy {
    public async void cancel () throws Error {
        yield call ("Cancel", null, ALLOW_INTERACTIVE_AUTHORIZATION, -1);
    }
}

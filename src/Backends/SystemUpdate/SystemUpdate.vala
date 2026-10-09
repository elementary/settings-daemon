/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

[DBus (name="io.elementary.settings_daemon.SystemUpdate")]
public class SettingsDaemon.Backends.SystemUpdate : Object {
    public signal void state_changed ();

    private SystemUpdateProvider? provider;

    construct {
        if (SettingsDaemon.Utils.is_sysupdate ()) {
            return;
        }

        provider = new PackageKit ();
        provider.state_changed.connect (() => state_changed ());
    }

    public async void check_for_updates (bool force, bool notify) throws DBusError, IOError {
        if (provider == null) {
            throw new IOError.NOT_SUPPORTED ("No system update provider available");
        }

        yield provider.check_for_updates (force, notify);
    }

    public async void update () throws DBusError, IOError {
        if (provider == null) {
            throw new IOError.NOT_SUPPORTED ("No system update provider available");
        }

        yield provider.update ();
    }

    public void cancel () throws DBusError, IOError {
        if (provider == null) {
            throw new IOError.NOT_SUPPORTED ("No system update provider available");
        }

        provider.cancel ();
    }

    public async PkUtils.CurrentState get_current_state () throws DBusError, IOError {
        if (provider == null) {
            throw new IOError.NOT_SUPPORTED ("No system update provider available");
        }

        return yield provider.get_current_state ();
    }

    public async SystemUpdateProvider.UpdateDetails get_update_details () throws DBusError, IOError {
        if (provider == null) {
            throw new IOError.NOT_SUPPORTED ("No system update provider available");
        }

        return yield provider.get_update_details ();
    }

    public async int64 get_last_refresh_time () throws DBusError, IOError {
        if (provider == null) {
            throw new IOError.NOT_SUPPORTED ("No system update provider available");
        }

        return yield provider.get_last_refresh_time ();
    }
}

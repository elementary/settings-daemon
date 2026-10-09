/*
 * Copyright 2023 elementary, Inc. (https://elementary.io)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public interface SettingsDaemon.Backends.SystemUpdateProvider : Object {
    public struct UpdateDetails {
        string[] packages;
        uint64 size;
        Pk.Info[] info;
    }

    public signal void state_changed ();

    public abstract async void check_for_updates (bool force, bool notify) throws DBusError, IOError;
    public abstract async void update () throws DBusError, IOError;
    public abstract void cancel () throws DBusError, IOError;
    public abstract async PkUtils.CurrentState get_current_state () throws DBusError, IOError;
    public abstract async UpdateDetails get_update_details () throws DBusError, IOError;
    public abstract async int64 get_last_refresh_time () throws DBusError, IOError;
}

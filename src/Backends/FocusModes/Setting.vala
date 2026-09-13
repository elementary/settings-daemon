/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public interface SettingsDaemon.Backends.FocusModes.Setting : Object {
    public abstract void apply (Variant value);
    public abstract void unapply ();
}

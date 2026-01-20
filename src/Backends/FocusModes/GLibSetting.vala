/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class SettingsDaemon.Backends.FocusModes.GLibSetting : Object, Setting {
    public Settings settings { get; construct; }
    public string key { get; construct; }
    public Variant active_value { get; construct; }

    private int applied = 0;
    private Variant? last_value = null;

    public GLibSetting (string schema_id, string key, Variant active_value) {
        Object (settings: new Settings (schema_id), key: key, active_value: active_value);
    }

    public void apply (Variant value) {
        applied++;

        if (applied == 1) {
            last_value = settings.get_value (key);
            settings.set_value (key, active_value);
        }
    }

    public void unapply () {
        applied--;

        assert (applied >= 0);

        if (applied == 0 && settings.get_value (key).equal (active_value) && last_value != null) {
            settings.set_value (key, last_value);
        }
    }
}

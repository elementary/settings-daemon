/*
 * Copyright 2021 elementary, Inc. (https://elementary.io)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 *
 * Authored by: Marius Meisenzahl <mariusmeisenzahl@gmail.com>
 */

public class SettingsDaemon.Backends.AccentColorSettings : Object {
    private Settings color_settings;
    private Settings background_settings;

    construct {
        color_settings = new Settings ("io.elementary.settings-daemon.accent-color");
        background_settings = new Settings ("org.gnome.desktop.background");

        color_settings.changed["set-accent-color-based-on-wallpaper"].connect (update_accent_color);
        background_settings.changed["picture-uri"].connect (update_accent_color);

        update_accent_color ();
    }

    private void update_accent_color () {
        var set_accent_color_based_on_wallpaper = color_settings.get_boolean ("set-accent-color-based-on-wallpaper");

        if (set_accent_color_based_on_wallpaper) {
            var picture_uri = background_settings.get_string ("picture-uri");

            // TODO(meisenzahl): set accent color
            // https://github.com/elementary/granite/pull/122
            // https://github.com/elementary/switchboard-plug-pantheon-shell/blob/master/src/Views/Appearance.vala#L22
            var interface_settings = new GLib.Settings ("org.gnome.desktop.interface");
            var current_stylesheet = interface_settings.get_string ("gtk-theme");
            var current_accent = current_stylesheet.replace ("io.elementary.stylesheet.", "");

            debug ("Changed wallpaper to: %s", picture_uri);
            debug ("Current accent color: %s", current_accent);
        }
    }
}

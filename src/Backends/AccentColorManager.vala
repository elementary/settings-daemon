/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021-2024 elementary, Inc. (https://elementary.io)
 * Authored by: Marius Meisenzahl <mariusmeisenzahl@gmail.com>
 */

public class SettingsDaemon.Backends.AccentColorManager : Object {
    public unowned Pantheon.AccountsService pantheon_accounts_service { get; construct; }
    public unowned AccountsService accounts_service { get; construct; }

    private Settings background_settings;
    private Settings interface_settings;

    private enum BackgroundStyle {
        NONE;
    }

    private struct Theme {
        int index;
        string name;
        string stylesheet;
        Gdk.RGBA color;
    }

    private static inline Gdk.RGBA rgba_from_int (int color) {
        return {
            ((color >> 16) & 255) / 255.0f,
            ((color >> 8) & 255) / 255.0f,
            (color & 255) / 255.0f,
            0.0f
        };
    }

    private static Theme[] themes = {
        { 1,  "Red",    "io.elementary.stylesheet.strawberry", rgba_from_int (0xed5353) }, // vala-lint=double-spaces
        { 2,  "Orange", "io.elementary.stylesheet.orange",     rgba_from_int (0xffa154) }, // vala-lint=double-spaces
        { 3,  "Yellow", "io.elementary.stylesheet.banana",     rgba_from_int (0xf9c440) }, // vala-lint=double-spaces
        { 4,  "Green",  "io.elementary.stylesheet.lime",       rgba_from_int (0x68b723) }, // vala-lint=double-spaces
        { 5,  "Mint",   "io.elementary.stylesheet.mint",       rgba_from_int (0x28bca3) }, // vala-lint=double-spaces
        { 6,  "Blue",   "io.elementary.stylesheet.blueberry",  rgba_from_int (0x3689e6) }, // vala-lint=double-spaces
        { 7,  "Purple", "io.elementary.stylesheet.grape",      rgba_from_int (0xa56de2) }, // vala-lint=double-spaces
        { 8,  "Pink",   "io.elementary.stylesheet.bubblegum",  rgba_from_int (0xde3e80) }, // vala-lint=double-spaces
        { 9,  "Brown",  "io.elementary.stylesheet.cocoa",      rgba_from_int (0x8a715e) }, // vala-lint=double-spaces
        { 10, "Gray",   "io.elementary.stylesheet.slate",      rgba_from_int (0x667885) }, // vala-lint=double-spaces
        { 11, "Latte",  "io.elementary.stylesheet.latte",      rgba_from_int (0xe7c591) }, // vala-lint=double-spaces
    };

    public AccentColorManager (Pantheon.AccountsService pantheon_accounts_service, AccountsService accounts_service) {
        Object (
            pantheon_accounts_service: pantheon_accounts_service,
            accounts_service: accounts_service
        );
    }

    construct {
        background_settings = new Settings ("org.gnome.desktop.background");
        interface_settings = new Settings ("org.gnome.desktop.interface");

        update_accent_color ();
        if (pantheon_accounts_service.prefers_accent_color == 0) {
            background_settings.changed["picture-options"].connect (update_accent_color);
            background_settings.changed["picture-uri"].connect (update_accent_color);
            background_settings.changed["primary-color"].connect (update_accent_color);
        }

        ((DBusProxy) pantheon_accounts_service).g_properties_changed.connect ((props) => {
            int accent_color;
            if (!props.lookup ("PrefersAccentColor", "i", out accent_color)) {
                return;
            };

            update_accent_color ();
            if (accent_color == 0) {
                background_settings.changed["picture-options"].connect (update_accent_color);
                background_settings.changed["picture-uri"].connect (update_accent_color);
                background_settings.changed["primary-color"].connect (update_accent_color);
            } else {
                background_settings.changed["picture-options"].disconnect (update_accent_color);
                background_settings.changed["picture-uri"].disconnect (update_accent_color);
                background_settings.changed["primary-color"].disconnect (update_accent_color);
            }
        });
    }

    private void update_accent_color () {
        Theme? new_theme = null;
        var prefers_accent_color = pantheon_accounts_service.prefers_accent_color;
        if (prefers_accent_color < 0 || prefers_accent_color - 1 >= themes.length) {
            critical ("Incorrect accent color in pantheon accounts service. color=%d", prefers_accent_color);
            return;
        }

        if (prefers_accent_color == 0) {
            new_theme = get_dynamic_accent_color_theme_name ();
        } else {
            new_theme = themes[prefers_accent_color - 1];
        }

        interface_settings.set_string ("gtk-theme", new_theme.stylesheet);
        debug ("New stylesheet: %s", new_theme.stylesheet);

        accounts_service.accent_color = new_theme.index;
    }

    private Theme get_dynamic_accent_color_theme_name () {
        Theme? new_theme = null;

        if (background_settings.get_enum ("picture-options") != BackgroundStyle.NONE) {
            var picture_uri = background_settings.get_string ("picture-uri");
            debug ("Current wallpaper: %s", picture_uri);
            new_theme = get_theme_for_picture (picture_uri);
        }

        // we failed to get a theme from the wallpaper, or the user is using a primary color as background
        if (new_theme == null) {
            var primary_color = background_settings.get_string ("primary-color");
            debug ("Current primary color: %s", primary_color);
            new_theme = get_theme_for_primary_color (primary_color);
        }

        return new_theme;
    }

    private Theme? get_theme_for_primary_color (string primary_color) {
        var best_match = double.MIN;
        var index = 0;

        Gdk.RGBA color = {};
        color.parse (primary_color);

        for (var i = 0; i < themes.length; i++) {
            var match = get_match (color, themes[i].color);
            if (match > best_match) {
                best_match = match;
                index = i;
            }
        }

        return themes[index];
    }

    private Theme? get_theme_for_picture (string picture_uri) {
        string path;
        try {
            path = Filename.from_uri (picture_uri);
        } catch (ConvertError e) {
            warning ("Failed to convert picture uri to path: '%s'", e.message);
            return null;
        }

        // try to read a theme name from exif metadata
        try {
            var metadata = new GExiv2.Metadata ();
            metadata.open_path (path);
            var accent_name = metadata.try_get_tag_string ("Xmp.xmp.io.elementary.AccentColor");

            foreach (unowned var theme in themes) {
                if (theme.name == accent_name) {
                    return theme;
                }
            }
        } catch (Error e) {
            warning ("Error parsing exif metadata of \"%s\": %s", path, e.message);
        }

        // if failed, get a dominant color from the picture
        try {
            const double PERCENTAGE_SAMPLE_PIXELS = 0.01;

            var pixbuf = new Gdk.Pixbuf.from_file (path);

            var raw_pixels = pixbuf.get_pixels_with_length ();
            var factor = pixbuf.has_alpha ? 4 : 3;
            var step_size = (int) (raw_pixels.length / factor * PERCENTAGE_SAMPLE_PIXELS);
            var pixels = new Array<Gdk.RGBA> ();

            for (var i = 0; i < raw_pixels.length / factor; i += step_size) {
                var offset = i * factor;
                pixels.append_val ({
                    raw_pixels[offset] / 255.0f,
                    raw_pixels[offset + 1] / 255.0f,
                    raw_pixels[offset + 2] / 255.0f,
                    0.0f
                });
            }

            var best_match = double.MIN;
            var index = 0;

            for (var i = 0; i < themes.length; i++) {
                var match = 0.0;

                foreach (unowned var pixel in pixels) {
                    match += get_match (pixel, themes[i].color);
                }

                if (match > best_match) {
                    best_match = match;
                    index = i;
                }
            }

            return themes[index];
        } catch (Error e) {
            warning (e.message);
        }

        return null;
    }

    private static inline double get_match (Gdk.RGBA color, Gdk.RGBA other) {
        var distance = Math.sqrt (
            Math.pow ((color.red - other.red), 2) +
            Math.pow ((color.green - other.green), 2) +
            Math.pow ((color.blue - other.blue), 2)
        );

        if (distance > 0.25) {
            return 0.0;
        }

        return 1.0 - distance;
    }
}

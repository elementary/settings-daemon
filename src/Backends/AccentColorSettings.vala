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
    private const string INTERFACE_SCHEMA = "org.gnome.desktop.interface";
    private const string STYLESHEET_KEY = "gtk-theme";
    private const string STYLESHEET_PREFIX = "io.elementary.stylesheet.";

    private Settings color_settings;
    private Settings background_settings;
    private Settings interface_settings;

    private NamedColor[] theme_colors = {
        new NamedColor () {
            name = "blueberry",
            hex = "#3689e6"
        },
        new NamedColor () {
            name = "mint",
            hex = "#28bca3"
        },
        new NamedColor () {
            name = "lime",
            hex = "#68b723"
        },
        new NamedColor () {
            name = "banana",
            hex = "#f9c440"
        },
        new NamedColor () {
            name = "orange",
            hex = "#ffa154"
        },
        new NamedColor () {
            name = "strawberry",
            hex = "#ed5353"
        },
        new NamedColor () {
            name = "bubblegum",
            hex = "#de3e80"
        },
        new NamedColor () {
            name = "grape",
            hex = "#a56de2"
        },
        new NamedColor () {
            name = "cocoa",
            hex = "#8a715e"
        },
        new NamedColor () {
            name = "slate",
            hex = "#667885"
        }
    };

    private Gee.HashMap<string, string> preseeded_colors;

    construct {
        color_settings = new Settings ("io.elementary.settings-daemon.accent-color");
        background_settings = new Settings ("org.gnome.desktop.background");
        interface_settings = new Settings (INTERFACE_SCHEMA);

        preseeded_colors = new Gee.HashMap<string, string> ();
        preseeded_colors.set ("file:///usr/share/backgrounds/Ashim%20DSilva.jpg", "orange");
        preseeded_colors.set ("file:///usr/share/backgrounds/Canazei%20Granite%20Ridges.jpg", "cocoa");
        preseeded_colors.set ("file:///usr/share/backgrounds/Jonas%20Nilsson%20Lee.jpg", "blueberry");
        preseeded_colors.set ("file:///usr/share/backgrounds/Julia%20Craice.jpg", "slate");
        preseeded_colors.set ("file:///usr/share/backgrounds/Martin%20Adams.jpg", "banana");
        preseeded_colors.set ("file:///usr/share/backgrounds/Morskie%20Oko.jpg", "lime");
        preseeded_colors.set ("file:///usr/share/backgrounds/Mr.%20Lee.jpg", "strawberry");
        preseeded_colors.set ("file:///usr/share/backgrounds/Nattu%20Adnan.jpg", "blueberry");
        preseeded_colors.set ("file:///usr/share/backgrounds/Photo%20by%20SpaceX.jpg", "slate");
        preseeded_colors.set ("file:///usr/share/backgrounds/Snow-Capped%20Mountain.jpg", "blueberry");
        preseeded_colors.set ("file:///usr/share/backgrounds/Sunset%20by%20the%20Pier.jpg", "orange");
        preseeded_colors.set ("file:///usr/share/backgrounds/Tj%20Holowaychuk.jpg", "grape");
        preseeded_colors.set ("file:///usr/share/backgrounds/Viktor%20Forgacs.jpg", "bubblegum");
        preseeded_colors.set ("file:///usr/share/backgrounds/leigh-kendell-581.jpg", "orange");

        color_settings.changed["set-accent-color-based-on-wallpaper"].connect (update_accent_color);
        background_settings.changed["picture-uri"].connect (update_accent_color);

        update_accent_color ();
    }

    private void update_accent_color () {
        var set_accent_color_based_on_wallpaper = color_settings.get_boolean ("set-accent-color-based-on-wallpaper");

        if (set_accent_color_based_on_wallpaper) {
            var picture_uri = background_settings.get_string ("picture-uri");

            var current_stylesheet = interface_settings.get_string (STYLESHEET_KEY);
            var current_accent = current_stylesheet.replace (STYLESHEET_PREFIX, "");

            debug ("Current wallpaper: %s", picture_uri);
            debug ("Current accent color: %s", current_accent);

            NamedColor? new_color = null;
            if (preseeded_colors.has_key (picture_uri)) {
                var color_name = preseeded_colors.get (picture_uri);

                for (int i = 0; i < theme_colors.length; i++) {
                    if (theme_colors[i].name == color_name) {
                        new_color = theme_colors[i];
                        break;
                    }
                }
            } else {
                new_color = get_accent_color_of_picture_simple (picture_uri);
            //  new_color = get_accent_color_of_picture_from_palette (picture_uri);
            }

            debug ("New accent color: %s", new_color.name);

            if (new_color != null && new_color.name != current_accent) {
                interface_settings.set_string (
                    STYLESHEET_KEY,
                    STYLESHEET_PREFIX + new_color.name
                );
            }
        }
    }

    public NamedColor? get_accent_color_of_picture_simple (string picture_uri) {
        NamedColor new_color = null;

        var file = File.new_for_uri (picture_uri);

        try {
            var pixbuf = new Gdk.Pixbuf.from_file (file.get_path ());
            var color_extractor = new Utils.ColorExtractor (pixbuf);

            var palette = new Gee.ArrayList<Granite.Drawing.Color> ();
            for (int i = 0; i < theme_colors.length; i++) {
                palette.add (new Granite.Drawing.Color.from_string (theme_colors[i].hex));
            }

            var index = color_extractor.get_dominant_color_index (palette);
            new_color = theme_colors[index];
        } catch (Error e) {
            warning (e.message);
        }

        return new_color;
    }

    public NamedColor? get_accent_color_of_picture_from_palette (string picture_uri) {
        NamedColor new_color = null;

        var file = File.new_for_uri (picture_uri);

        try {
            var pixbuf = new Gdk.Pixbuf.from_file (file.get_path ());

            var palette = new Utils.Palette.from_pixbuf (pixbuf);
            palette.generate_sync ();
            var swatch = palette.vibrant_swatch;
            if (swatch == null) {
                swatch = palette.dominant_swatch;
            }

            if (swatch == null) {
                return null;
            }

            Gdk.RGBA rgba = {swatch.R, swatch.G, swatch.B, swatch.A};
            var wallpaper_color = new NamedColor.from_rgba (rgba);
            debug ("Color of wallpaper: %s", wallpaper_color.hex);

            double best_match = 0.0;
            for (int i = 0; i < theme_colors.length; i++) {
                var match = theme_colors[i].compare (wallpaper_color);
                if (match > best_match) {
                    new_color = theme_colors[i];
                    best_match = match;
                }
            }
        } catch (Error e) {
            warning (e.message);
        }

        return new_color;
    }

    public class NamedColor : Object {
        public string name { get; set; }
        public string hex { get; set; }

        public NamedColor.from_rgba (Gdk.RGBA rgba) {
            hex = "#%02x%02x%02x".printf (
                (int) (rgba.red * 255),
                (int) (rgba.green * 255),
                (int) (rgba.blue * 255)
            );
        }

        public double compare (NamedColor other) {
            var rgba1 = to_rgba ();
            var rgba2 = other.to_rgba ();

            var distance = Math.sqrt (
                Math.pow ((rgba2.red - rgba1.red), 2) +
                Math.pow ((rgba2.green - rgba1.green), 2) +
                Math.pow ((rgba2.blue - rgba1.blue), 2)
            );

            return 1.0 - distance / Math.sqrt (
                Math.pow (255, 2) +
                Math.pow (255, 2) +
                Math.pow (255, 2)
            );
        }

        public Gdk.RGBA to_rgba () {
            Gdk.RGBA rgba = { 0, 0, 0, 0 };
            rgba.parse (hex);

            return rgba;
        }
    }
}

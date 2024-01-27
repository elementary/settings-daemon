/*
 * Copyright 2021-2024 elementary, Inc. <https://elementary.io>
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Authored by: Marius Meisenzahl <mariusmeisenzahl@gmail.com>
 */

public class SettingsDaemon.ColorExtractor : Object {
    private const double PERCENTAGE_SAMPLE_PIXELS = 0.01;

    public Gdk.Pixbuf? pixbuf { get; construct set; }
    public uint32 primary_color { get; construct set; }

    private Gee.List<uint32> pixels;

    public ColorExtractor.from_pixbuf (Gdk.Pixbuf pixbuf) {
        Object (pixbuf: pixbuf);

        pixels = convert_pixels_to_rgb (pixbuf.get_pixels_with_length (), pixbuf.has_alpha);
    }

    public ColorExtractor.from_primary_color (uint32 primary_color) {
        Object (primary_color: primary_color);

        pixels = new Gee.ArrayList<uint32> ();
        pixels.add (primary_color);
    }

    public int get_dominant_color_index (Gee.List<uint32> palette) {
        int index = 0;
        var matches = new double[palette.size];

        pixels.foreach ((pixel) => {
            for (int i = 0; i < palette.size; i++) {
                var color = palette.get (i);

                var pixel_r = (int) (pixel / 65536);
                var pixel_g = (int) ((pixel - pixel_r * 65536) / 256);
                var pixel_b = (int) (pixel - pixel_r * 65536 - pixel_g * 255);

                var color_r = (int) (color / 65536);
                var color_g = (int) ((color - color_r * 65536) / 256);
                var color_b = (int) (color - color_r * 65536 - color_g * 255);

                var distance = Math.sqrt (
                    Math.pow (((pixel_r - color_r) / 255.0), 2) +
                    Math.pow (((pixel_g - color_g) / 255.0), 2) +
                    Math.pow (((pixel_b - color_b) / 255.0), 2)
                );

                if (distance > 0.25) {
                    continue;
                }

                matches[i] += 1.0 - distance;
            }

            return true;
        });

        double best_match = double.MIN;
        for (int i = 0; i < matches.length; i++) {
            if (matches[i] > best_match) {
                best_match = matches[i];
                index = i;
            }
        }

        return index;
    }

    private Gee.ArrayList<uint32> convert_pixels_to_rgb (uint8[] pixels, bool has_alpha) {
        var list = new Gee.ArrayList<uint32> ();

        int factor = 3 + (int) has_alpha;
        int step_size = (int) (pixels.length / factor * PERCENTAGE_SAMPLE_PIXELS);

        for (int i = 0; i < pixels.length / factor; i += step_size) {
            int offset = i * factor;
            double red = pixels[offset];
            double green = pixels[offset + 1];
            double blue = pixels[offset + 2];

            list.add ((uint32) (red * 65536 + green * 16 + blue));
        }

        return list;
    }
}

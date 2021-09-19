/*-
 * Copyright 2021 Alexander Mikhaylenko <alexm@gnome.org>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor
 * Boston, MA 02110-1335 USA.
 */

namespace XdgDesktopPortal {
    public enum Error {
        FAILED,
        INVALID_ARGUMENT,
        NOT_FOUND,
        EXISTS,
        NOT_ALLOWED,
        CANCELLED,
        WINDOW_DESTROYED
    }

    const GLib.DBusErrorEntry[] ERROR_ENTRIES = {
      { Error.FAILED, "org.freedesktop.portal.Error.Failed" },
      { Error.INVALID_ARGUMENT, "org.freedesktop.portal.Error.InvalidArgument" },
      { Error.NOT_FOUND, "org.freedesktop.portal.Error.NotFound" },
      { Error.EXISTS, "org.freedesktop.portal.Error.Exists" },
      { Error.NOT_ALLOWED, "org.freedesktop.portal.Error.NotAllowed" },
      { Error.CANCELLED, "org.freedesktop.portal.Error.Cancelled" },
      { Error.WINDOW_DESTROYED, "org.freedesktop.portal.Error.WindowDestroyed" }
    };

    private size_t quark = 0;

    private GLib.Quark error_quark () {
        GLib.DBusError.register_error_domain (
            "xdg-desktop-portal-error-quark",
            (size_t) &quark,
            ERROR_ENTRIES
        );

        return (GLib.Quark) quark;
    }

    public GLib.Error create_error (Error code, string message) {
        return new GLib.Error.literal (error_quark (), code, message);
    }
}

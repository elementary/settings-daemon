/*
* Copyright 2020 elementary, Inc. (https://elementary.io)
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
*/

public class SettingsDaemon.Backends.KeyboardSettings : GLib.Object {
    public unowned AccountsService accounts_service { get; construct; }

    private GLib.Settings keyboard_settings;

    public KeyboardSettings (AccountsService accounts_service) {
        Object (accounts_service: accounts_service);
    }

    construct {
        keyboard_settings = new GLib.Settings ("org.gnome.desktop.input-sources");

        // If the user hasn't set any keyboard layouts of their own
        if (keyboard_settings.get_user_value ("sources") == null) {
            // And there are keyboard layouts set in accounts service
            if (accounts_service.keyboard_layouts.length > 0) {
                // This means inital-setup has created a keyboard layout for the user, but
                // it hasn't yet been applied to the user, so do that here.
                sync_accountsservice_to_gsettings ();
            }
        }

        sync_gsettings_to_accountsservice ();

        keyboard_settings.changed.connect ((key) => {
            if (key == "current" ||
                key == "sources" ||
                key == "xkb-options") {
                sync_gsettings_to_accountsservice ();
            }
        });
    }

    private void sync_accountsservice_to_gsettings () {
        Variant[] entries = {};
        foreach (var layout in accounts_service.keyboard_layouts) {
            entries += new Variant ("(ss)", layout.backend, layout.name);
        }

        var sources = new Variant.array (new VariantType ("(ss)"), entries);
        keyboard_settings.set_value ("sources", sources);
        keyboard_settings.set_value ("current", accounts_service.active_keyboard_layout);
        keyboard_settings.set_value ("xkb-options", accounts_service.xkb_options);
    }

    private void sync_gsettings_to_accountsservice () {
        AccountsService.KeyboardLayout[] act_layouts = {};
        GLib.Variant sources = keyboard_settings.get_value ("sources");
        if (sources.is_of_type (VariantType.ARRAY)) {
            for (size_t i = 0; i < sources.n_children (); i++) {
                string backend, layout;
                sources.get_child_value (i).@get ("(ss)", out backend, out layout);
                act_layouts += AccountsService.KeyboardLayout () {
                    backend = backend,
                    name = layout
                };
            }

            accounts_service.keyboard_layouts = act_layouts;
            accounts_service.active_keyboard_layout = keyboard_settings.get_uint ("current");
        } else {
            warning ("Unkown keyboard layouts type, unable to save to AccountsService");
        }
        
        var xkb_options = keyboard_settings.get_strv ("xkb-options");
        AccountsService.XkbOption[] act_options = {};
        for (size_t i = 0; i < xkb_options.length; i++) {
            act_options += AccountsService.XkbOption () {
                option = xkb_options[i]
            };
        }
        accounts_service.xkb_options = act_options;
    }
}

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

public class SettingsDaemon.Application : GLib.Application {
    public const OptionEntry[] OPTIONS = {
        { "version", 'v', 0, OptionArg.NONE, out show_version, "Display the version", null},
        { null }
    };

    public static bool show_version;

    private Application () {}

    private SessionClient? session_client;

    construct {
        application_id = Build.PROJECT_NAME;

        add_main_option_entries (OPTIONS);
    }

    public override int handle_local_options (VariantDict options) {
        if (show_version) {
            stdout.printf ("%s\n", Build.VERSION);
            return 0;
        }

        return -1;
    }

    public override void activate () {
        register_with_session_manager.begin ();

        hold ();
    }

    private async bool register_with_session_manager () {
        session_client = yield register_with_session (Build.PROJECT_NAME);

        session_client.query_end_session.connect (() => end_session (false));
        session_client.end_session.connect (() => end_session (false));
        session_client.stop.connect (() => end_session (true));

        return true;
    }

    void end_session (bool quit) {
        if (quit) {
            release ();
            return;
        }

        try {
            session_client.end_session_response (true, "");
        } catch (Error e) {
            warning ("Unable to respond to session manager: %s", e.message);
        }
    }

    public static int main (string[] args) {
        var application = new Application ();
        return application.run (args);
    }
}



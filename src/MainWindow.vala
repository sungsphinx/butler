/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2024 Cassidy James Blaede <c@ssidyjam.es>
 */

public class Butler.MainWindow : Adw.ApplicationWindow {
    private const GLib.ActionEntry[] ACTION_ENTRIES = {
        { "toggle_fullscreen", toggle_fullscreen },
        { "set_server", on_set_server_activate },
        { "log_out", on_log_out_activate },
        { "about", on_about_activate },
    };

    private Butler.WebView web_view;

    public MainWindow (Gtk.Application application) {
        Object (
            application: application,
            height_request: 180,
            icon_name: APP_ID,
            resizable: true,
            title: App.NAME,
            width_request: 300
        );
        add_action_entries (ACTION_ENTRIES, this);
    }

    construct {
        var site_menu = new Menu ();
        site_menu.append (_("_Log Out…"), "win.log_out");

        var app_menu = new Menu ();
        // TODO: How do I add shortcuts to the menu?
        app_menu.append (_("Toggle _Fullscreen"), "win.toggle_fullscreen");
        app_menu.append (_("Change _Server…"), "win.set_server");
        app_menu.append (_("_About %s").printf (App.NAME), "win.about");

        var menu = new Menu ();
        menu.append_section (null, site_menu);
        menu.append_section (null, app_menu);

        var menu_button = new Gtk.MenuButton () {
            icon_name = "open-menu-symbolic",
            menu_model = menu,
            tooltip_text = _("Main Menu"),
        };

        var header = new Adw.HeaderBar ();
        header.pack_end (menu_button);

        web_view = new Butler.WebView ();

        string server = App.settings.get_string ("server");
        string current_url = App.settings.get_string ("current-url");
        if (current_url != "") {
            web_view.load_uri (current_url);
        } else {
            web_view.load_uri (server);
        }

        var status_page = new Adw.StatusPage () {
            title = _("%s for Home Assistant").printf (App.NAME),
            description = _("Loading the dashboard…"),
            icon_name = APP_ID
        };

        var stack = new Gtk.Stack () {
            // Half speed since it's such a huge distance
            transition_duration = 400,
            transition_type = Gtk.StackTransitionType.UNDER_UP
        };
        stack.add_css_class ("loading");
        stack.add_named (status_page, "loading");
        stack.add_named (web_view, "web");

        var grid = new Gtk.Grid () {
            orientation = Gtk.Orientation.VERTICAL
        };
        grid.attach (header, 0, 0);
        grid.attach (stack, 0, 1);

        set_content (grid);

        int window_width, window_height;
        App.settings.get ("window-size", "(ii)", out window_width, out window_height);

        set_default_size (window_width, window_height);

        if (App.settings.get_boolean ("window-maximized")) {
            maximize ();
        }

        close_request.connect (() => {
            save_window_state ();
            return Gdk.EVENT_PROPAGATE;
        });
        notify["maximized"].connect (save_window_state);

        web_view.load_changed.connect ((load_event) => {
            if (load_event == WebKit.LoadEvent.FINISHED) {
                stack.visible_child_name = "web";
            }
        });

        web_view.load_changed.connect (on_loading);
        web_view.notify["uri"].connect (on_loading);
        web_view.notify["estimated-load-progress"].connect (on_loading);
        web_view.notify["is-loading"].connect (on_loading);

        App.settings.bind ("zoom", web_view, "zoom-level", SettingsBindFlags.DEFAULT);
    }

    private void save_window_state () {
        if (maximized) {
            App.settings.set_boolean ("window-maximized", true);
        } else {
            App.settings.set_boolean ("window-maximized", false);
            App.settings.set (
                "window-size", "(ii)",
                get_size (Gtk.Orientation.HORIZONTAL),
                get_size (Gtk.Orientation.VERTICAL)
            );
        }
    }

    private void on_loading () {
        if (web_view.is_loading) {
            // TODO: Add a loading progress bar or spinner somewhere?
        } else {
            App.settings.set_string ("current-url", web_view.uri);
        }
    }

    public void zoom_in () {
        if (web_view.zoom_level < 5.0) {
            web_view.zoom_level = web_view.zoom_level + 0.1;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already max");
        }

        return;
    }

    public void zoom_out () {
        if (web_view.zoom_level > 0.2) {
            web_view.zoom_level = web_view.zoom_level - 0.1;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already min");
        }

        return;
    }

    public void zoom_default () {
        if (web_view.zoom_level != 1.0) {
            web_view.zoom_level = 1.0;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already default");
        }

        return;
    }

    private void log_out () {
        // Home Assistant doesn't use cookies for login; clear ALL to include
        // local storage and cache
        web_view.network_session.get_website_data_manager ().clear.begin (
            WebKit.WebsiteDataTypes.ALL, 0, null, () => {
                debug ("Cleared data; going home.");
                web_view.load_uri (App.settings.get_string ("server"));
            }
        );
    }

    public void toggle_fullscreen () {
        if (fullscreened) {
            unfullscreen ();
        } else {
            fullscreen ();
        }
    }

    private void on_set_server_activate () {
        string current_server = App.settings.get_string ("server");
        string default_server = App.settings.get_default_value ("server").get_string ();

        var server_entry = new Gtk.Entry.with_buffer (new Gtk.EntryBuffer ((uint8[]) current_server)) {
            activates_default = true,
            hexpand = true,
            placeholder_text = default_server
        };

        var server_dialog = new Adw.MessageDialog (
            this,
            "Set Server URL",
            "Enter the full URL including protocol (e.g. <tt>http://</tt>) and any custom port (e.g. <tt>:8123</tt>)"
        ) {
            body_use_markup = true,
            default_response = "save",
            extra_child = server_entry,
        };
        server_dialog.add_response ("close", "Cancel");

        server_dialog.add_response ("demo", _("Reset to Demo"));
        server_dialog.set_response_appearance ("demo", Adw.ResponseAppearance.DESTRUCTIVE);

        server_dialog.add_response ("save", _("Set Server"));
        server_dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);

        server_dialog.present ();

        server_dialog.response.connect ((response_id) => {
            if (response_id == "save") {
                string new_server = server_entry.buffer.text;

                if (new_server == "") {
                    new_server = default_server;
                }

                if (new_server != current_server) {
                    // FIXME: There's currently no validation of this
                    App.settings.set_string ("server", new_server);
                    log_out ();
                }
            } else if (response_id == "demo") {
                App.settings.reset ("server");
                log_out ();
            }
        });
    }

    private void on_log_out_activate () {
        string server = App.settings.get_string ("server");

        var log_out_dialog = new Adw.MessageDialog (
            this,
            "Log out of Home Assistant?",
            "You will need to re-enter your username and password for <b>%s</b> to log back in.".printf (server)
        ) {
            body_use_markup = true,
            default_response = "log_out"
        };
        log_out_dialog.add_response ("close", "Stay Logged In");
        log_out_dialog.add_response ("log_out", _("Log Out"));
        log_out_dialog.set_response_appearance ("log_out", Adw.ResponseAppearance.DESTRUCTIVE);

        log_out_dialog.present ();

        log_out_dialog.response.connect ((response_id) => {
            if (response_id == "log_out") {
                log_out ();
            }
        });
    }

    private void on_about_activate () {
        var about_window = new Adw.AboutWindow () {
            transient_for = this,

            application_icon = APP_ID,
            application_name = _("%s for Home Assistant").printf (App.NAME),
            developer_name = App.DEVELOPER,
            version = VERSION,

            comments = _("Butler is a hybrid native + web app for your Home Assistant dashboard"),

            website = App.URL,
            issue_url = "https://github.com/cassidyjames/butler/issues",

            // Credits
            developers = { "%s <%s>".printf (App.DEVELOPER, App.EMAIL) },
            designers = { "%s %s".printf (App.DEVELOPER, App.URL) },

            /// The translator credits. Please translate this with your name(s).
            translator_credits = _("translator-credits"),

            // Legal
            copyright = "Copyright © 2020–2024 %s".printf (App.DEVELOPER),
            license_type = Gtk.License.GPL_3_0,
        };
        about_window.add_link (_("About Home Assistant"), "https://www.home-assistant.io/");
        about_window.add_link (_("Home Assistant Privacy Policy"), "https://www.home-assistant.io/privacy/");

        about_window.present ();
    }
}

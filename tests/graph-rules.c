/* Exercise the native configuration merge and ALSA property rules privately. */
#include <assert.h>
#include <stdio.h>
#include <wp/wp.h>

int main (int argc, char **argv)
{
    assert (argc == 2 || argc == 3);
    wp_init (WP_INIT_ALL);
    g_autoptr (GError) error = NULL;
    g_autoptr (WpConf) conf = wp_conf_new_open ("wireplumber.conf", NULL, &error);
    assert (conf && !error);
    g_autoptr (WpProperties) props = wp_properties_new (
        "node.name", argv[1], "media.class", "Audio/Sink", NULL);
    if (argc == 3) {
        wp_properties_set (props, "elementary.eq.profile", argv[2]);
    }
    g_autoptr (WpSpaJson) rules = wp_conf_get_section (conf, "monitor.alsa.rules");
    assert (rules);
    wp_json_utils_match_rules_update_properties (rules, props);
    const char *profile = wp_properties_get (props, "elementary.eq.profile");
    puts (profile ? profile : "");
    return 0;
}

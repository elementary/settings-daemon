/* SPDX-License-Identifier: GPL-3.0-or-later
 * Private synthetic SPA card: real Device/Route protocol, no hardware.
 * This fixture is not part of the daemon or installed policy.
 */
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <pipewire/pipewire.h>
#include <spa/monitor/device.h>
#include <spa/monitor/utils.h>
#include <spa/param/profile.h>
#include <spa/param/route.h>
#include <spa/pod/builder.h>
#include <spa/pod/parser.h>

struct fixture {
    struct spa_device device;
    struct spa_hook_list hooks;
    struct spa_param_info params[4];
    struct pw_main_loop *loop;
    struct pw_properties *props;
    unsigned route;
};

static void info (struct fixture *f)
{
    struct spa_device_info i = SPA_DEVICE_INFO_INIT ();
    i.change_mask = SPA_DEVICE_CHANGE_MASK_PROPS | SPA_DEVICE_CHANGE_MASK_PARAMS;
    i.props = &f->props->dict;
    i.params = f->params;
    i.n_params = 4;
    spa_device_emit_info (&f->hooks, &i);
}

static int add_listener (void *object, struct spa_hook *hook,
                   const struct spa_device_events *events, void *data)
{
    struct fixture *f = object;
    struct spa_hook_list save;
    spa_hook_list_isolate (&f->hooks, &save, hook, events, data);
    info (f);
    spa_hook_list_join (&f->hooks, &save);
    return 0;
}

static int sync_device (void *object, int seq)
{
    struct fixture *f = object;
    spa_device_emit_result (&f->hooks, seq, 0, 0, NULL);
    return 0;
}

static int enumerate (void *object, int seq, uint32_t id, uint32_t index,
                      uint32_t max, const struct spa_pod *filter)
{
    struct fixture *f = object;
    uint32_t count = id == SPA_PARAM_EnumRoute ? 2 : 1;
    for (uint32_t n = 0; index < count && n < max; n++, index++) {
        uint8_t buffer[1024];
        struct spa_pod_builder b = SPA_POD_BUILDER_INIT (buffer, sizeof buffer);
        struct spa_pod *pod;
        if (id == SPA_PARAM_EnumRoute || id == SPA_PARAM_Route) {
            int route = id == SPA_PARAM_Route ? f->route : index;
            int device = 0, profile = 0;
            pod = spa_pod_builder_add_object (&b, SPA_TYPE_OBJECT_ParamRoute, id,
                SPA_PARAM_ROUTE_index, SPA_POD_Int (route),
                SPA_PARAM_ROUTE_direction, SPA_POD_Id (SPA_DIRECTION_OUTPUT),
                SPA_PARAM_ROUTE_name, SPA_POD_String (route ? "fixture-headphones" : "fixture-speaker"),
                SPA_PARAM_ROUTE_description, SPA_POD_String (route ? "Fixture Headphones" : "Fixture Speakers"),
                SPA_PARAM_ROUTE_priority, SPA_POD_Int (route ? 10 : 100),
                SPA_PARAM_ROUTE_available, SPA_POD_Id (SPA_PARAM_AVAILABILITY_yes),
                SPA_PARAM_ROUTE_device, SPA_POD_Int (0),
                SPA_PARAM_ROUTE_devices, SPA_POD_Array (sizeof (int), SPA_TYPE_Int, 1, &device),
                SPA_PARAM_ROUTE_profiles, SPA_POD_Array (sizeof (int), SPA_TYPE_Int, 1, &profile));
        } else if (id == SPA_PARAM_EnumProfile || id == SPA_PARAM_Profile) {
            pod = spa_pod_builder_add_object (&b, SPA_TYPE_OBJECT_ParamProfile, id,
                SPA_PARAM_PROFILE_index, SPA_POD_Int (0),
                SPA_PARAM_PROFILE_name, SPA_POD_String ("fixture-output"),
                SPA_PARAM_PROFILE_description, SPA_POD_String ("Fixture output"),
                SPA_PARAM_PROFILE_available, SPA_POD_Id (SPA_PARAM_AVAILABILITY_yes));
        } else return -ENOENT;
        struct spa_result_device_params result = { .id = id, .index = index, .next = index + 1, .param = pod };
        spa_device_emit_result (&f->hooks, seq, 0, SPA_RESULT_TYPE_DEVICE_PARAMS, &result);
    }
    return 0;
}

static int set_param (void *object, uint32_t id, uint32_t flags, const struct spa_pod *pod)
{
    struct fixture *f = object;
    int route = 0;
    if (id == SPA_PARAM_Profile) return 0;
    if (id != SPA_PARAM_Route || !pod ||
        spa_pod_parse_object (pod, SPA_TYPE_OBJECT_ParamRoute, NULL,
            SPA_PARAM_ROUTE_index, SPA_POD_Int (&route)) < 0 || route < 0 || route > 1) return -EINVAL;
    if (f->route != (unsigned)route) {
        f->route = route;
        f->params[3].flags ^= SPA_PARAM_INFO_SERIAL;
        info (f);
    }
    return 0;
}

static const struct spa_device_methods methods = {
    SPA_VERSION_DEVICE_METHODS, .add_listener = add_listener, .sync = sync_device,
    .enum_params = enumerate, .set_param = set_param
};
static void quit (void *data, int signal) { pw_main_loop_quit (((struct fixture *)data)->loop); }
static void bound (void *data, uint32_t id) { printf ("%u\n", id); fflush (stdout); }
static const struct pw_proxy_events proxy_events = { PW_VERSION_PROXY_EVENTS, .bound = bound };

int main (int argc, char **argv)
{
    assert (getenv ("EQ_PRIVATE_TEST") && !strcmp (getenv ("PIPEWIRE_REMOTE"), "elementary-eq-bridge"));
    struct fixture f = { 0 };
    struct spa_hook proxy_hook;
    pw_init (&argc, &argv);
    f.device.iface = SPA_INTERFACE_INIT (SPA_TYPE_INTERFACE_Device, SPA_VERSION_DEVICE, &methods, &f);
    spa_hook_list_init (&f.hooks);
    f.params[0] = SPA_PARAM_INFO (SPA_PARAM_EnumProfile, SPA_PARAM_INFO_READ);
    f.params[1] = SPA_PARAM_INFO (SPA_PARAM_Profile, SPA_PARAM_INFO_READWRITE);
    f.params[2] = SPA_PARAM_INFO (SPA_PARAM_EnumRoute, SPA_PARAM_INFO_READ);
    f.params[3] = SPA_PARAM_INFO (SPA_PARAM_Route, SPA_PARAM_INFO_READWRITE);
    f.props = pw_properties_new ("device.name", "elementary.eq.card", "media.class", "Audio/Device",
        "device.description", "Private EQ bridge fixture", "device.api", "fixture", NULL);
    f.loop = pw_main_loop_new (NULL);
    struct pw_loop *loop = pw_main_loop_get_loop (f.loop);
    pw_loop_add_signal (loop, SIGINT, quit, &f);
    pw_loop_add_signal (loop, SIGTERM, quit, &f);
    struct pw_context *context = pw_context_new (loop, NULL, 0);
    struct pw_core *core = pw_context_connect (context, NULL, 0);
    assert (core);
    struct pw_proxy *proxy = pw_core_export (core, SPA_TYPE_INTERFACE_Device, &f.props->dict, &f.device, 0);
    assert (proxy);
    pw_proxy_add_listener (proxy, &proxy_hook, &proxy_events, &f);
    pw_main_loop_run (f.loop);
    pw_proxy_destroy (proxy);
    pw_core_disconnect (core);
    pw_context_destroy (context);
    pw_main_loop_destroy (f.loop);
    pw_properties_free (f.props);
    return 0;
}

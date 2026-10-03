/* Fault injection around real libpulse operations, not a replacement backend.
 * A successful load is followed by a bounded period of NOENTITY responses,
 * as when PipeWire has not yet exported the filter's Pulse endpoints.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <pulse/pulseaudio.h>

static double hidden_until;
static double now (void) {
    struct timespec t;
    clock_gettime (CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

struct load_callback {
    pa_context_index_cb_t callback;
    void *userdata;
};

static void loaded (pa_context *c, uint32_t index, void *userdata) {
    struct load_callback *data = userdata;
    if (index != PA_INVALID_INDEX) {
        FILE *file = fopen (getenv ("AEC_TEST_DELAY_FILE"), "r");
        unsigned delay = 0;
        if (file) {
            if (fscanf (file, "%u", &delay) != 1) abort ();
            fclose (file);
        }
        hidden_until = now () + delay / 1000.0;
    }
    data->callback (c, index, data->userdata);
    free (data);
}

pa_operation *pa_context_load_module (pa_context *c, const char *name, const char *args,
                                     pa_context_index_cb_t callback, void *userdata) {
    typeof (&pa_context_load_module) real = dlsym (RTLD_NEXT, "pa_context_load_module");
    struct load_callback *data = malloc (sizeof *data);
    *data = (struct load_callback) { callback, userdata };
    fprintf (stderr, "AEC_TEST_LOAD\n");
    pa_operation *op = real (c, name, args, loaded, data);
    if (!op) free (data);
    return op;
}

pa_operation *pa_context_get_source_info_by_name (pa_context *c, const char *name,
                                                pa_source_info_cb_t callback, void *userdata) {
    typeof (&pa_context_get_source_info_by_name) real = dlsym (RTLD_NEXT, "pa_context_get_source_info_by_name");
    if (now () < hidden_until && strcmp (name, "elementary_echo_cancel_source") == 0)
        name = "aec_test_not_published";
    return real (c, name, callback, userdata);
}

pa_operation *pa_context_get_sink_info_by_name (pa_context *c, const char *name,
                                              pa_sink_info_cb_t callback, void *userdata) {
    typeof (&pa_context_get_sink_info_by_name) real = dlsym (RTLD_NEXT, "pa_context_get_sink_info_by_name");
    if (now () < hidden_until && strcmp (name, "elementary_echo_cancel_sink") == 0)
        name = "aec_test_not_published";
    return real (c, name, callback, userdata);
}

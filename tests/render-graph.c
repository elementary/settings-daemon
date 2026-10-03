/* Native SPA rendering fixture: no DSP implementation or audio-server connection. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pipewire/pipewire.h>
#include <spa/filter-graph/filter-graph.h>
#include <spa/support/plugin.h>

int main(int argc, char **argv)
{
    assert(argc == 3 && getenv("EQ_PRIVATE_TEST") && access("/dev/snd", F_OK) != 0);
    FILE *file = fopen(argv[1], "r");
    assert(file);
    assert(fseek(file, 0, SEEK_END) == 0);
    long size = ftell(file);
    assert(size > 0 && size < 65536);
    rewind(file);
    char *json = calloc(size + 1, 1);
    assert(json && fread(json, 1, size, file) == (size_t)size);
    fclose(file);
    pw_init(&argc, &argv);
    struct pw_main_loop *loop = pw_main_loop_new(NULL);
    struct pw_context *context = pw_context_new(pw_main_loop_get_loop(loop), NULL, 0);
    assert(context);
    struct spa_handle *handle = pw_context_load_spa_handle(context, "filter.graph", &SPA_DICT_ITEMS(
        SPA_DICT_ITEM("library.name", "filter-graph/libspa-filter-graph"),
        SPA_DICT_ITEM("filter.graph", json),
        SPA_DICT_ITEM("clock.quantum-limit", "1024"),
        SPA_DICT_ITEM("filter-graph.n_inputs", "2"),
        SPA_DICT_ITEM("filter-graph.n_outputs", "2")));
    assert(handle);
    struct spa_filter_graph *graph;
    assert(spa_handle_get_interface(handle, SPA_TYPE_INTERFACE_FilterGraph, (void **)&graph) == 0);
    assert(spa_filter_graph_activate(graph, &SPA_DICT_ITEMS(
        SPA_DICT_ITEM("audio.rate", argv[2]), SPA_DICT_ITEM("filter-graph.n_inputs", "2"))) == 0);
    float interleaved[2048], left[1024], right[1024], out_left[1024], out_right[1024];
    size_t count;
    while ((count = fread(interleaved, sizeof(float), 2048, stdin)) != 0) {
        assert(count % 2 == 0);
        for (size_t i = 0; i < count / 2; i++) {
            left[i] = interleaved[i * 2]; right[i] = interleaved[i * 2 + 1];
        }
        const void *in[] = { left, right };
        void *out[] = { out_left, out_right };
        assert(spa_filter_graph_process(graph, in, out, count / 2) == 0);
        for (size_t i = 0; i < count / 2; i++) {
            interleaved[i * 2] = out_left[i]; interleaved[i * 2 + 1] = out_right[i];
        }
        assert(fwrite(interleaved, sizeof(float), count, stdout) == count);
    }
    assert(!ferror(stdin));
    assert(spa_filter_graph_deactivate(graph) == 0);
    pw_unload_spa_handle(handle);
    pw_context_destroy(context);
    pw_main_loop_destroy(loop);
    pw_deinit();
    free(json);
    return 0;
}

/* Root profile loader boundary, linked to the production implementation. */
#include "Backends/speaker-equalizer-profile.h"
#include <stdio.h>
int main (int argc, char **argv)
{
    if (argc != 2) return 2;
    GError *error = NULL;
    char *data = eq_profile_read (argv[1], &error);
    if (error) { fprintf (stderr, "%s\n", error->message); g_error_free (error); }
    if (!data) return 1;
    g_free (data);
    return 0;
}

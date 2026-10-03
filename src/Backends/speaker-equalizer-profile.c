/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "speaker-equalizer-profile.h"
#include <errno.h>
#include <fcntl.h>
#include <glib/gi18n-lib.h>
#include <sys/stat.h>
#include <unistd.h>
#ifndef EQ_PROFILE_DIR
#define EQ_PROFILE_DIR "/usr/share/io.elementary.settings-daemon/equalizers/v1"
#endif

char *eq_profile_read (const char *id, GError **error)
{
    int fd = -1;
    char *result = NULL;
    g_auto (GStrv) parts = NULL;
    struct stat st;
    if (!id || !*id || strlen (id) > 64) goto out;
    for (const char *p = id; *p; p++)
        if (!g_ascii_isalnum (*p) && *p != '-' && *p != '_') goto out;
    /* Walk every directory without following links. No user config fallback. */
    fd = open ("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    parts = g_strsplit (EQ_PROFILE_DIR, "/", -1);
    for (char **p = parts; *p && fd >= 0; p++) {
        if (!**p) continue;
        int next = openat (fd, *p, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        close (fd); fd = next;
        if (fd < 0 || fstat (fd, &st) || st.st_uid != 0 || (st.st_mode & 022)) goto out;
    }
    if (fd < 0) goto out;
    char filename[72];
    g_snprintf (filename, sizeof filename, "%s.ini", id);
    int file = openat (fd, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    close (fd); fd = file;
    if (fd < 0 || fstat (fd, &st) || !S_ISREG (st.st_mode) || st.st_uid != 0 ||
        (st.st_mode & 022) || st.st_size <= 0 || st.st_size > 8192) goto out;
    result = g_malloc (st.st_size + 1);
    if (read (fd, result, st.st_size) != st.st_size) g_clear_pointer (&result, g_free);
    else if (memchr (result, '\0', st.st_size)) g_clear_pointer (&result, g_free);
    else result[st.st_size] = '\0';
out:
    if (fd >= 0) close (fd);
    if (!result) g_set_error_literal (error, G_FILE_ERROR, G_FILE_ERROR_INVAL,
        _("No valid root-installed equalizer profile is available."));
    return result;
}

#define _XOPEN_SOURCE 700

#include <limits.h>
#include <locale.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* Provided by the standard narrow ncurses library selected by AdaCurses. */
extern int mvaddnstr(int line, int column, const char *text, int length);

int hra_n_terminal_utf8_initialize(void)
{
    return setlocale(LC_ALL, "") == NULL ? -1 : 0;
}

/* One decoder owns cell-width policy for both layout and curses clipping. */
static int next_terminal_glyph(const char *text,
                               size_t remaining,
                               mbstate_t *state,
                               size_t *consumed,
                               int *width)
{
    wchar_t wc;

    *consumed = mbrtowc(&wc, text, remaining, state);
    if (*consumed == (size_t)-1 || *consumed == (size_t)-2) {
        return -1;
    }
    if (*consumed == 0) {
        return 0;
    }

    *width = wcwidth(wc);
    return *width < 0 ? -1 : 1;
}

int hra_n_terminal_utf8_display_width(const char *text)
{
    mbstate_t state;
    const char *ptr;
    size_t remaining;
    int columns = 0;

    if (text == NULL) {
        return -1;
    }

    memset(&state, 0, sizeof(state));
    ptr = text;
    remaining = strlen(text);

    while (remaining > 0) {
        size_t consumed;
        int width;
        int status =
            next_terminal_glyph(ptr, remaining, &state, &consumed, &width);

        if (status < 0) {
            return -1;
        }
        if (status == 0) {
            break;
        }
        if (columns > INT_MAX - width) {
            return -1;
        }

        columns += width;
        ptr += consumed;
        remaining -= consumed;
    }

    return columns;
}

int hra_n_terminal_utf8_add_line(int line,
                                 int column,
                                 const char *text,
                                 int max_columns)
{
    mbstate_t state;
    const char *ptr;
    size_t remaining;
    int columns = 0;
    int bytes_to_draw = 0;

    if (text == NULL || text[0] == '\0' || max_columns <= 0) {
        return 0;
    }

    memset(&state, 0, sizeof(state));
    ptr = text;
    remaining = strlen(text);

    while (remaining > 0) {
        size_t consumed;
        int width;
        int status =
            next_terminal_glyph(ptr, remaining, &state, &consumed, &width);

        if (status < 0) {
            return -1;
        }
        if (status == 0) {
            break;
        }
        if (columns > INT_MAX - width ||
            consumed > (size_t)(INT_MAX - bytes_to_draw)) {
            return -1;
        }
        if (columns + width > max_columns) {
            break;
        }

        columns += width;
        bytes_to_draw += (int)consumed;
        ptr += consumed;
        remaining -= consumed;
    }

    if (bytes_to_draw == 0) {
        return 0;
    }

    return mvaddnstr(line, column, text, bytes_to_draw);
}

int hra_n_terminal_utf8_slice(const char *text,
                              int start_column,
                              int max_columns,
                              char *out_buf,
                              int out_buf_size)
{
    mbstate_t state;
    const char *ptr;
    size_t remaining;
    int current_column = 0;
    int visible_columns = 0;
    int out_pos = 0;

    if (out_buf == NULL || out_buf_size <= 0) {
        return -1;
    }
    out_buf[0] = '\0';

    if (text == NULL || max_columns <= 0) {
        return 0;
    }

    if (start_column < 0) {
        start_column = 0;
    }

    memset(&state, 0, sizeof(state));
    ptr = text;
    remaining = strlen(text);

    while (remaining > 0) {
        size_t consumed;
        int width;
        int status =
            next_terminal_glyph(ptr, remaining, &state, &consumed, &width);

        if (status < 0) {
            return -1;
        }
        if (status == 0) {
            break;
        }

        int glyph_start = current_column;
        int glyph_end = current_column + width;
        current_column += width;

        if (glyph_end <= start_column) {
            ptr += consumed;
            remaining -= consumed;
            continue;
        }

        if (glyph_start < start_column && glyph_end > start_column) {
            int padding = glyph_end - start_column;
            for (int k = 0; k < padding; k++) {
                if (visible_columns >= max_columns) {
                    break;
                }
                if (out_pos + 1 >= out_buf_size) {
                    return -1;
                }
                out_buf[out_pos++] = ' ';
                visible_columns++;
            }
            ptr += consumed;
            remaining -= consumed;
            continue;
        }

        if (visible_columns + width > max_columns) {
            break;
        }

        if (out_pos + (int)consumed >= out_buf_size) {
            return -1;
        }
        memcpy(out_buf + out_pos, ptr, consumed);
        out_pos += (int)consumed;
        visible_columns += width;

        ptr += consumed;
        remaining -= consumed;
    }

    out_buf[out_pos] = '\0';
    return 0;
}

#include <curses.h>

static mmask_t previous_mask;
static int mouse_started;

int hra_n_mouse_key_code(void)
{
    return KEY_MOUSE;
}

int hra_n_mouse_scroll_start(void)
{
    mmask_t requested_mask = BUTTON4_PRESSED;
    mmask_t accepted_mask;

    previous_mask = 0;

#if defined(NCURSES_MOUSE_VERSION) && NCURSES_MOUSE_VERSION >= 2
    requested_mask |= BUTTON5_PRESSED;
#else
    /*
     * ncurses mouse ABI v1 has no Button5. Its xterm wheel handler maps
     * wheel-down to REPORT_MOUSE_POSITION instead. The ordinary ncurses xterm
     * mouse mode is private mode 1000, which reports button activity but not
     * pointer motion, so this value remains a directional wheel signal here.
     */
    requested_mask |= REPORT_MOUSE_POSITION;
#endif

    accepted_mask = mousemask(requested_mask, &previous_mask);
    mouse_started = (accepted_mask & requested_mask) == requested_mask;

    if (!mouse_started) {
        mmask_t discarded_previous;
        (void)mousemask(previous_mask, &discarded_previous);
    }

    return mouse_started;
}

void hra_n_mouse_scroll_stop(void)
{
    mmask_t discarded_previous;

    if (!mouse_started) {
        return;
    }

    (void)mousemask(previous_mask, &discarded_previous);
    mouse_started = 0;
}

int hra_n_mouse_scroll_read(void)
{
    MEVENT event;

    if (getmouse(&event) != OK) {
        return 0;
    }

    if ((event.bstate & BUTTON4_PRESSED) != 0) {
        return -1;
    }

#if defined(NCURSES_MOUSE_VERSION) && NCURSES_MOUSE_VERSION >= 2
    if ((event.bstate & BUTTON5_PRESSED) != 0) {
        return 1;
    }
#else
    if ((event.bstate & REPORT_MOUSE_POSITION) != 0) {
        return 1;
    }
#endif

    return 0;
}

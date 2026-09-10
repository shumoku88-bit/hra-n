/*
 * Operational companion to AuthorityPublication.tla.
 * Three data files are installed as one immutable generation; one selector is
 * the only activation edge visible to readers.
 */

#define NONE 0
#define OLD  0
#define NEW  1
#define MAX_ID 2

byte lock_owner = NONE;
byte selected_version = OLD;
bit admitted_new = 0;
bit installed_new = 0;
bit selector_durable = 1;
bit receipt = 0;
byte next_id = 1;
bit allocated[MAX_ID + 1];

inline safety() {
    assert((selected_version == OLD) || (admitted_new && installed_new));
    assert(!receipt ||
           (selected_version == NEW && admitted_new && installed_new && selector_durable));
    assert((allocated[1] + allocated[2]) == (next_id - 1));
}

proctype Writer(byte me)
{
    do
    :: atomic {
          (lock_owner == NONE && !receipt && next_id <= MAX_ID) ->
          lock_owner = me
       };
       break
    :: (receipt || next_id > MAX_ID) -> goto end_writer
    od;
    safety();

    /* Re-read and allocate only after exclusive ownership. */
    atomic {
        assert(lock_owner == me);
        assert(!allocated[next_id]);
        allocated[next_id] = 1;
        next_id++
    }
    safety();

    if
    :: goto crash_before_activation
    :: skip
    fi;

    admitted_new = 1;
    safety();

    if
    :: goto crash_before_activation
    :: skip
    fi;

    /* All three files are durable before the generation is selectable. */
    installed_new = 1;
    safety();

    if
    :: goto crash_before_activation
    :: skip
    fi;

    selected_version = NEW;
    selector_durable = 0;
    safety();

    if
    :: /* Power loss may retain either old or new atomic selector bytes. */
       if
       :: selected_version = OLD
       :: selected_version = NEW
       fi;
       selector_durable = 1;
       receipt = 0;
       lock_owner = NONE;
       safety();
       goto end_writer
    :: skip
    fi;

    selector_durable = 1;
    safety();

    /* Receipt is impossible before post-activation durability. */
    receipt = 1;
    safety();
    lock_owner = NONE;
    goto end_writer;

crash_before_activation:
    receipt = 0;
    lock_owner = NONE;
    safety();

end_writer:
    skip
}

init {
    atomic {
        run Writer(1);
        run Writer(2)
    }
}

#include <stdio.h>

/*
 * Dape practice.
 *
 * Each TODO below is a recurring exercise: do it three times over the next
 * week (once today, once midweek, and once at the end of the week).  Start
 * with SPC m D s; the Makefile builds build/main first.  F5 (SPC m D c)
 * continues, F8 (SPC m D n) steps over, F7 (SPC m D i) steps in, and
 * SPC m D ? shows every debugger key.
 *
 * The same tasks are tracked as repeating Org TODOs in
 * examples/dape-practice.org, which is on the agenda.
 */

struct item {
    const char *name;
    double price;
    int quantity;
};

static double item_total(const struct item *item)
{
    // TODO (repeat 3x this week) Function breakpoint: stop whenever
    // item_total is called.  Press SPC m D F, enter item_total, then start
    // with SPC m D s.  Continue with F5 to see each call, and remove the
    // breakpoint with d in the breakpoint list (SPC m D G).
    return item->price * item->quantity;
}

static double subtotal(const struct item *items, size_t count)
{
    double total = 0.0;
    // TODO (repeat 3x this week) Data breakpoint (watchpoint) and scope:
    // stop on the loop line below with F2, open the scope with SPC m D V,
    // put point on total, and press b.  If GDB advertises data breakpoints,
    // a Data row appears in SPC m D G and continuing stops when total
    // changes.  In the scope W toggles a watch, = edits the value, and m
    // views memory when the adapter supports it.
    for (size_t index = 0; index < count; index++) {
        // TODO (repeat 3x this week) Conditional breakpoint: stop only when
        // the running total is above 10.  With point on the next line press
        // S-F2 (SPC m D E), enter total > 10, then start with SPC m D s.
        // F5 stops on the second item, where total is already 13.5.
        total += item_total(&items[index]);
    }
    return total;
}

int main(void)
{
    const struct item items[] = {
        {"notebook", 4.5, 3},
        {"pen", 1.25, 4},
        {"lamp", 22.0, 1},
    };
    const size_t count = sizeof(items) / sizeof(items[0]);

    // TODO (repeat 3x this week) Hit-count breakpoint and watch: press
    // SPC m D h on the loop line below, choose == and 2, then start.  Dape
    // stops on the second item.  With the session stopped, put point on
    // index and press C-F3 (SPC m D w) to watch it on every stop.
    for (size_t index = 0; index < count; index++) {
        // TODO (repeat 3x this week) Log breakpoint: print values without
        // stopping.  Press C-F2 (SPC m D l) here and enter
        // item={items[index].name} price={items[index].price}.  If the GDB
        // adapter has no log-point support, use F3 (SPC m D a), choose
        // "Debuggee expression", and enter items[index].name instead.
        printf("%d x %s = %.2f\n", items[index].quantity,
               items[index].name, item_total(&items[index]));
    }
    printf("subtotal: %.2f\n", subtotal(items, count));
    // TODO (repeat 3x this week) Save/load and low-level views: SPC m D P
    // saves the source breakpoints to the project's dape-bps file and
    // SPC m D L restores them later.  At a stop, SPC m D M disassembles
    // around the instruction pointer and SPC m D m reads memory at an
    // address.  SPC m D e disables a breakpoint in place; SPC m D B removes
    // all of them.
    return 0;
}

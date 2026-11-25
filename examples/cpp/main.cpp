#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

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

struct Item {
    std::string name;
    double price;
    int quantity;

    double total() const { return price * quantity; }
};

static double subtotal(const std::vector<Item> &items)
{
    // TODO (repeat 3x this week) Function breakpoint: stop when subtotal is
    // entered.  Press SPC m D F, enter subtotal, then start with SPC m D s.
    // Step into the range-for with F7 (SPC m D i) to see each Item.
    double total = 0.0;
    // TODO (repeat 3x this week) Data breakpoint (watchpoint): stop on the
    // loop line below with F2, open the scope with SPC m D V, put point on
    // total, and press b.  If GDB advertises data breakpoints, a Data row
    // appears in SPC m D G and continuing stops when total changes.
    for (const auto &item : items) {
        // TODO (repeat 3x this week) Conditional breakpoint: stop only when
        // the running total is above 10.  With point on the next line press
        // S-F2 (SPC m D E), enter total > 10.0, then start and press F5.
        // The debugger stops after the first item, when total is 13.5.
        total += item.total();
    }
    return total;
}

int main()
{
    const std::vector<Item> items = {
        {"notebook", 4.5, 3},
        {"pen", 1.25, 4},
        {"lamp", 22.0, 1},
    };

    std::cout << std::fixed << std::setprecision(2);
    // TODO (repeat 3x this week) Hit-count breakpoint and watch: press
    // SPC m D h on the loop line below, choose == and 2, then start.  Dape
    // stops on the second item.  With the session stopped, put point on
    // item and press C-F3 (SPC m D w) to watch item.quantity.
    for (const auto &item : items) {
        // TODO (repeat 3x this week) Log breakpoint and breakpoint action:
        // press C-F2 (SPC m D l) here and enter
        // quantity={item.quantity} price={item.price}.  To run code on a
        // normal hit instead, use F3 (SPC m D a), choose "Debuggee
        // expression", and enter item.total(); its value appears in the
        // REPL.  SPC m D A clears the action.
        std::cout << item.quantity << " x " << item.name << " = "
                  << item.total() << '\n';
    }
    std::cout << "subtotal: " << subtotal(items) << '\n';
    // TODO (repeat 3x this week) Save/load and low-level views: SPC m D P
    // saves the source breakpoints to the project's dape-bps file and
    // SPC m D L restores them later.  At a C++ stop, SPC m D M disassembles
    // around the instruction pointer and SPC m D m reads memory at an
    // address.
    return 0;
}

import java.util.List;

/*
 * Dape practice.
 *
 * Each TODO below is a recurring exercise: do it three times over the next
 * week (once today, once midweek, and once at the end of the week).  Start
 * Eglot with SPC m l, then start the debugger with SPC m D s.  F5 (SPC m D c)
 * continues, F8 (SPC m D n) steps over, F7 (SPC m D i) steps in, and
 * SPC m D ? shows every debugger key.
 *
 * The same tasks are tracked as repeating Org TODOs in
 * examples/dape-practice.org, which is on the agenda.
 */

public class Main {
    record Item(String name, double price, int quantity) {
        double total() {
            return price * quantity;
        }
    }

    // TODO (repeat 3x this week) Function breakpoint: stop when subtotal is
    // entered.  Press SPC m D F, enter subtotal (or Main.subtotal), then
    // start with SPC m D s.  Continue with F5 and step into item.total().
    static double subtotal(List<Item> items) {
        double total = 0.0;
        // TODO (repeat 3x this week) Hit-count breakpoint: press SPC m D h
        // on the loop line below, choose == and 2, then start.  Dape stops
        // on the second item.  With the session stopped, put point on total
        // and press C-F3 (SPC m D w) to watch it on every stop.
        for (Item item : items) {
            // TODO (repeat 3x this week) Conditional breakpoint: press S-F2
            // (SPC m D E) here and enter item.quantity() > 2, then start and
            // press F5.  It stops for the notebook and the pen.
            total += item.total();
        }
        return total;
    }

    // Practice hook for exception breakpoints; call it from the Dape REPL.
    static void crash() {
        throw new RuntimeException("practice");
    }

    public static void main(String[] args) {
        List<Item> items = List.of(
                new Item("notebook", 4.5, 3),
                new Item("pen", 1.25, 4),
                new Item("lamp", 22.0, 1));
        // TODO (repeat 3x this week) Log breakpoint and breakpoint action:
        // press C-F2 (SPC m D l) on the loop line below and enter
        // item={item.name()} total={total}.  For code on a normal hit, use
        // F3 (SPC m D a), choose "Debuggee expression", and enter
        // item.total().  For a conditional action, use S-F3 (SPC m D C),
        // condition item.quantity() > 2, and choose "Emacs Lisp" with
        // (message "big item").  SPC m D A clears the action.
        for (Item item : items) {
            System.out.printf("%d x %s = %.2f%n",
                    item.quantity(), item.name(), item.total());
        }
        System.out.printf("subtotal: %.2f%n", subtotal(items));
        // TODO (repeat 3x this week) Script action and persistence: stop on
        // the line above with F2, press F3 (SPC m D a), choose "Script file",
        // and select examples/java/OnBreak.java.  Then use SPC m D P to save
        // the source breakpoints to the project's dape-bps file and
        // SPC m D L to load them in a later session.
        // TODO (repeat 3x this week) Exception breakpoint: with a session
        // stopped, press SPC m D X and enable Uncaught Exceptions.  Open the
        // REPL with SPC m D R and evaluate Main.crash(); Dape stops where
        // the exception is thrown.  Continue with F5.
        System.out.println("done");
    }
}

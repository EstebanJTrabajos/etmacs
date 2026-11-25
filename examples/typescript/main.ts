// Dape practice.
//
// Each TODO below is a recurring exercise: do it three times over the next
// week (once today, once midweek, and once at the end of the week).  Start
// with SPC m D s; the .dir-locals.el compiles with npm run build first.  F5
// (SPC m D c) continues, F8 (SPC m D n) steps over, F7 (SPC m D i) steps in,
// and SPC m D ? shows every debugger key.
//
// The same tasks are tracked as repeating Org TODOs in
// examples/dape-practice.org, which is on the agenda.

type Item = {
  name: string;
  price: number;
  quantity: number;
};

class Cart {
  private readonly items: Item[] = [];

  add(item: Item): void {
    this.items.push(item);
  }

  // TODO (repeat 3x this week) Function breakpoint: stop when subtotal is
  // entered.  Press SPC m D F, enter subtotal (or Cart.subtotal), then start
  // with SPC m D s.  Step into the reduce callback with F7 (SPC m D i).
  subtotal(): number {
    // TODO (repeat 3x this week) Conditional breakpoint and hit count: press
    // S-F2 (SPC m D E) on the reduce line below and enter item.quantity > 2,
    // then start.  For a hit-count breakpoint instead, press SPC m D h and
    // choose == and 2.  Continue with F5.
    return this.items.reduce(
      (total, item) => total + item.price * item.quantity,
      0,
    );
  }

  summary(): string[] {
    // TODO (repeat 3x this week) Log breakpoint: press C-F2 (SPC m D l) here
    // and enter {item.name} x {item.quantity} = {item.price * item.quantity}.
    // It prints on every call without stopping; braces evaluate TypeScript
    // expressions in the stopped frame.
    return this.items.map(
      (item) =>
        `${item.quantity} x ${item.name} = ${(item.price * item.quantity).toFixed(2)}`,
    );
  }
}

// Practice hook for exception breakpoints; call it from the Dape REPL.
function crash(): never {
  throw new Error("practice");
}

// TODO (repeat 3x this week) JavaScript code action and script action: stop
// inside subtotal with F2, press F3 (SPC m D a), choose "JavaScript code
// (statements)", and enter console.log("hit", item.name, total).  Output
// appears in the Dape REPL.  For a conditional action use S-F3 (SPC m D C),
// condition item.quantity > 2, and the same statements.  For a script
// action, choose "Script file" and select examples/javascript/on_break.js.
// SPC m D A clears the action.
const cart = new Cart();
cart.add({ name: "notebook", price: 4.5, quantity: 3 });
cart.add({ name: "pen", price: 1.25, quantity: 4 });
cart.add({ name: "lamp", price: 22, quantity: 1 });

// TODO (repeat 3x this week) Watch and exception breakpoints: at a stop in
// subtotal, put point on items and press C-F3 (SPC m D w), or use C-S-F3
// (SPC m D W) for this.items.length.  To practice exceptions, press
// SPC m D X, enable Uncaught Exceptions, open the REPL with SPC m D R, and
// evaluate crash().
console.log(cart.summary());
console.log(`subtotal: ${cart.subtotal().toFixed(2)}`);

"use strict";

// Dape practice.
//
// Each TODO below is a recurring exercise: do it three times over the next
// week (once today, once midweek, and once at the end of the week).  Start
// with SPC m D s.  F5 (SPC m D c) continues, F8 (SPC m D n) steps over, F7
// (SPC m D i) steps in, and SPC m D ? shows every debugger key.
//
// The same tasks are tracked as repeating Org TODOs in
// examples/dape-practice.org, which is on the agenda.

// TODO (repeat 3x this week) Function breakpoint: stop whenever sumEven is
// called.  Press SPC m D F, enter sumEven, then start with SPC m D s.
// Continue with F5 and inspect the values argument in the scope buffer.
function sumEven(values) {
  let total = 0;
  // TODO (repeat 3x this week) Hit-count breakpoint: press SPC m D h on the
  // loop line below, choose == and 3, then start.  Dape stops on the third
  // iteration, where value is 12.
  for (const value of values) {
    if (value % 2 === 0) {
      // TODO (repeat 3x this week) Conditional breakpoint: press S-F2
      // (SPC m D E) here and enter value > 10, then start and press F5.  The
      // debugger stops on 12 before it is added to total.
      total += value;
    }
  }
  return total;
}

// Practice hook for exception breakpoints; call it from the Dape REPL.
function crash() {
  throw new Error("practice");
}

function describe(values) {
  // TODO (repeat 3x this week) Log breakpoint: press C-F2 (SPC m D l) here
  // and enter value={value} index={index}.  It prints on every call without
  // stopping; braces evaluate expressions in the stopped frame.
  return values.map((value, index) => ({
    index,
    value,
    parity: value % 2 === 0 ? "even" : "odd",
  }));
}

// TODO (repeat 3x this week) JavaScript code action: stop inside sumEven
// with F2, press F3 (SPC m D a), choose "JavaScript code (statements)", and
// enter console.log("hit", value, total).  The output appears in the Dape
// REPL instead of the program terminal.  For a conditional action, use
// S-F3 (SPC m D C), condition value > 10, and the same statements.  SPC m D A
// clears the action.
//
// TODO (repeat 3x this week) Script action and persistence: use F3 (SPC m D a)
// with "Script file" and choose examples/javascript/on_break.js.  Then set a
// few breakpoints and use SPC m D P to save them to the project's dape-bps
// file; SPC m D L loads them back in a later session.
const values = [3, 8, 12, 5, 20, 7];
console.log(JSON.stringify(describe(values)));
// TODO (repeat 3x this week) Watch and exception breakpoints: at a stop, put
// point on values and press C-F3 (SPC m D w) to watch it, or use C-S-F3
// (SPC m D W) for values.filter(v => v % 2 === 0).  To practice exceptions,
// press SPC m D X, enable Uncaught Exceptions, open the REPL with SPC m D R,
// and evaluate crash().  Use SPC m D x to evaluate values.length or any other
// expression in the stopped frame.
console.log(`sum of even values: ${sumEven(values)}`);

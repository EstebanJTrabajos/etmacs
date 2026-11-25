#!/usr/bin/env ipython3
"""Small Python program for Eglot, pytest, and Dape/debugpy checks."""

# Dape practice.
#
# Each TODO below is a recurring exercise: do it three times over the next
# week (once today, once midweek, and once at the end of the week).  Start
# with SPC m D s; debugpy must be importable in the interpreter selected for
# the project.  F5 (SPC m D c) continues, F8 (SPC m D n) steps over, F7
# (SPC m D i) steps in, and SPC m D ? shows every debugger key.
#
# The same tasks are tracked as repeating Org TODOs in
# examples/dape-practice.org, which is on the agenda.

from dataclasses import dataclass


@dataclass
class Account:
    name: str
    balance: float


# TODO (repeat 3x this week) Function breakpoint: stop whenever deposit runs.
# Press SPC m D F, enter deposit, then start with SPC m D s.  Continue with
# F5 and watch the amount argument change on each call.
def deposit(account: Account, amount: float) -> float:
    """Add AMOUNT to ACCOUNT and return the new balance."""
    # TODO (repeat 3x this week) Conditional breakpoint: stop only for larger
    # deposits.  With point on the next line press S-F2 (SPC m D E), enter
    # amount >= 50, then start and press F5.  It stops for savings (50) and
    # travel (75), but not for checking (25).
    account.balance += amount
    # TODO (repeat 3x this week) Log breakpoint: press C-F2 (SPC m D l) here
    # and enter {account.name} balance={account.balance}.  The line is
    # printed on every call without stopping.  Expressions inside braces are
    # evaluated in the stopped frame.
    return account.balance


# TODO (repeat 3x this week) Conditional action and script action: stop on
# the return line above with F2, press S-F3 (SPC m D C), enter the condition
# account.balance >= 300, choose "Emacs Lisp", and enter
# (message "high balance").  For a script action instead, press F3 (SPC m D a)
# and choose the file examples/python/on_break.py.  SPC m D A clears it.
def total_balance(accounts: list[Account]) -> float:
    total = 0.0
    for account in accounts:
        # TODO (repeat 3x this week) Hit-count breakpoint and watch: press
        # SPC m D h on this line, choose == and 2, then start.  Dape stops on
        # the second account.  With the session stopped, put point on total
        # and press C-F3 (SPC m D w) to watch it on every stop.
        total += account.balance
    return total


def crash() -> None:
    """Practice hook for exception breakpoints; call it from the Dape REPL."""
    raise RuntimeError("practice")


def main() -> None:
    accounts = [
        Account("checking", 100.0),
        Account("savings", 250.0),
        Account("travel", 40.0),
    ]
    for index, account in enumerate(accounts, start=1):
        deposit(account, index * 25.0)
        # TODO (repeat 3x this week) Exception breakpoint: with the session
        # stopped here, press SPC m D X and enable Raised Exceptions (or
        # Uncaught Exceptions).  Open the REPL with SPC m D R and evaluate
        # crash(); Dape stops where the exception is raised.  Continue with
        # F5.
        print(f"{account.name}: {account.balance:.2f}")
    print(f"total: {total_balance(accounts):.2f}")


if __name__ == "__main__":
    main()

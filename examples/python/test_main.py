"""Pytest checks for the Python Dape example."""

from main import Account, deposit, total_balance


def test_deposit_updates_balance() -> None:
    account = Account("checking", 10.0)
    assert deposit(account, 5.0) == 15.0
    assert account.balance == 15.0


def test_total_balance_sums_accounts() -> None:
    accounts = [Account("a", 1.0), Account("b", 2.0)]
    assert total_balance(accounts) == 3.0

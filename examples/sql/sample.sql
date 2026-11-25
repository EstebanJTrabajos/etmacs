CREATE TABLE items (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    quantity INTEGER NOT NULL
);

INSERT INTO items (name, price, quantity) VALUES
    ('notebook', 4.50, 3),
    ('pen', 1.25, 4),
    ('lamp', 22.00, 1);

SELECT name, price * quantity AS total
FROM items
ORDER BY total DESC;

-- Seeded state. What matters to the discriminator is not what these rows mean
-- but that an empty instance of the same image carries none of them.
CREATE TABLE products (
    id          serial PRIMARY KEY,
    sku         text NOT NULL UNIQUE,
    name        text NOT NULL,
    price_cents integer NOT NULL
);

CREATE TABLE orders (
    id         serial PRIMARY KEY,
    product_id integer NOT NULL REFERENCES products (id),
    quantity   integer NOT NULL
);

CREATE INDEX orders_product_id_idx ON orders (product_id);

INSERT INTO products (sku, name, price_cents) VALUES
    ('SKU-001', 'Wide-brim hat',  4200),
    ('SKU-002', 'Canvas tote',    2800),
    ('SKU-003', 'Enamel mug',     1500),
    ('SKU-004', 'Wool scarf',     6100),
    ('SKU-005', 'Leather wallet', 9900);

INSERT INTO orders (product_id, quantity) VALUES
    (1, 2), (2, 1), (3, 4), (1, 1), (5, 3);

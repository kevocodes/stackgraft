CREATE TABLE accounts (id serial PRIMARY KEY, name text NOT NULL);
CREATE TABLE invoices (id serial PRIMARY KEY, account_id integer NOT NULL, cents integer NOT NULL);
CREATE TABLE billing_schedules (id serial PRIMARY KEY, cron_expression text NOT NULL, last_fired timestamptz);
INSERT INTO accounts (name) VALUES ('acme'), ('globex'), ('initech');
INSERT INTO invoices (account_id, cents) VALUES (1, 1000), (2, 2500);
INSERT INTO billing_schedules (cron_expression) VALUES ('0 */6 * * *');

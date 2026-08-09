CREATE TABLE fulfilments (
    id       int AUTO_INCREMENT PRIMARY KEY,
    order_id int NOT NULL,
    carrier  varchar(64) NOT NULL
);

CREATE TABLE carriers (
    code varchar(16) PRIMARY KEY,
    name varchar(64) NOT NULL
);

INSERT INTO carriers (code, name) VALUES ("dhl", "DHL"), ("ups", "UPS"), ("fdx", "FedEx");
INSERT INTO fulfilments (order_id, carrier) VALUES (1, "dhl"), (2, "ups"), (3, "dhl");

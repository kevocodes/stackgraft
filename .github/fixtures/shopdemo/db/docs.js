// Seeded state for the document store. What matters to the discriminator is
// not what these hold but that an empty instance of the same image holds none.
db = db.getSiblingDB("shop");
db.reviews.insertMany([
    { sku: "SKU-001", stars: 5 },
    { sku: "SKU-002", stars: 4 },
    { sku: "SKU-003", stars: 3 }
]);
db.pages.insertMany([
    { slug: "about", title: "About" },
    { slug: "terms", title: "Terms" }
]);

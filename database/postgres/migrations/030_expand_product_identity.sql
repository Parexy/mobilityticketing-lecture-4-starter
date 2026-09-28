-- Copy to 030_expand_product_identity.sql and complete it.
-- Add a stored UUID to each product and a unique key.
-- Add the nullable ticket reference and a NOT VALID foreign key.
-- Keep the original product code contract usable.

begin;
set local lock_timeout = '3s';

alter table products
    add column id uuid;

update products
set id = gen_random_uuid()
where id is null;

alter table products
    alter column id set default gen_random_uuid();

alter table products
    alter column id set not null;

alter table products
    add constraint products_id_unique
        unique (id);

alter table tickets
    add column product_id uuid;

alter table tickets
    add constraint tickets_product_id_fk
        foreign key (product_id)
        references products(id)
        not valid;

commit;

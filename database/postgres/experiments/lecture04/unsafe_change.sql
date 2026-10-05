begin;

alter table tickets
    drop column product_code;

alter table tickets
    add column product_id uuid;

alter table tickets
    alter column product_id set not null;

rollback;
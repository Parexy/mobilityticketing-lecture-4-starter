-- Copy to 032_require_ticket_product.sql and complete it.
-- Apply only after retiring old writers and passing final verification.
-- Validate the product-ID foreign key, then require the ticket reference.
-- Rehearse legacy-column removal separately after dependency checks.

begin;
set local lock_timeout = '3s';

alter table tickets
    validate constraint tickets_product_id_fk;

alter table tickets
    alter column product_id set not null;

commit;

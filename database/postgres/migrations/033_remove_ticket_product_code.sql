begin;
set local lock_timeout = '3s';

alter table tickets
    drop column product_code;

commit;
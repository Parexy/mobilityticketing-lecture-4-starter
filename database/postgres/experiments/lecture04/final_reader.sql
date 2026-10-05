-- TODO: Join products through product_id and include the product code.
-- Do not use tickets.product_code: this query must survive its removal.
select
    t.id,
    t.product_id,
    p.code as product_code,
    t.price,
    t.currency
from tickets t
join products p
    on p.id = t.product_id
order by t.id;
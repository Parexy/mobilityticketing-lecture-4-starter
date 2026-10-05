select
    t.id,
    p.code as product_code,
    t.product_id,
    t.price,
    t.currency
from tickets t
join products p
    on p.id = t.product_id
where t.id in (
    'TICKET-1',
    'TICKET-2',
    'TICKET-3'
)
order by t.id;
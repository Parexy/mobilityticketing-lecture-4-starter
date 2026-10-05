-- Start only after your ID-only reader and writer are ready.
begin;
set local lock_timeout = '3s';

-- Check views that mention product_code.
select
    schemaname,
    viewname,
    definition
from pg_views
where definition ilike '%product_code%';

-- Check ordinary functions/procedures that mention product_code.
with routines as materialized (
    select
        p.oid,
        n.nspname as schema_name,
        p.proname as routine_name
    from pg_proc p
    join pg_namespace n
        on n.oid = p.pronamespace
    where p.prokind in ('f', 'p')
)
select
    schema_name,
    routine_name,
    pg_get_functiondef(oid) as definition
from routines
where pg_get_functiondef(oid) ilike '%product_code%';

-- Rehearse removal without CASCADE.
alter table tickets
    drop column product_code;

rollback;
-- Keep this rehearsal reversible. Record what would need to happen before
-- you committed the same change in a real rollout.

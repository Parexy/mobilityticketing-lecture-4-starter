# Lecture 4: Rolling Product Identity Migration

## Purpose

This lab changes the relationship between tickets and products from the business-facing `product_code` to a stable UUID-based `product_id`.

The migration must support a period where old and new application versions overlap. Existing tickets must remain linked to the same product, and their historical `price` and `currency` values must not change.

The final intended model is:

- `products.id` is the stable product identity;
- `products.code` remains the business-facing catalogue code;
- `tickets.product_id` is the product foreign key;
- `tickets.product_code` is eventually removed.

---

## Rollout strategy

The migration uses an expand-and-contract rollout:

1. Record the existing data.
2. Demonstrate why an immediate destructive migration is unsafe.
3. Add `products.id` and nullable `tickets.product_id`.
4. Keep `tickets.product_code` available for old application versions.
5. Support both old and new readers/writers.
6. Backfill existing tickets.
7. Verify all references and historical values.
8. Stop old-only writers.
9. Validate the new foreign key and require `product_id`.
10. Move to ID-only readers and writers.
11. Check dependencies on the legacy column.
12. Remove `tickets.product_code`.

---

# 1. Baseline

A clean database was started and the supplied baseline test was executed.

The original tickets were:

| Ticket | Product code | Price | Currency |
| --- | --- | ---: | --- |
| `TICKET-1` | `SINGLE` | 36.00 | DKK |
| `TICKET-2` | `SINGLE` | 36.00 | DKK |
| `TICKET-3` | `DAY` | 65.00 | DKK |

The initial unresolved-product check returned zero rows.

`TICKET-3` is important because its stored purchase price is 65.00 DKK. The migration must preserve this value even though the current catalogue price of the DAY product is different.

---

# 2. Unsafe migration rehearsal

The deliberately unsafe migration attempted to:

1. remove `tickets.product_code`;
2. add `tickets.product_id`;
3. immediately require `product_id`.

The migration failed:

```text
ERROR: column "product_id" of relation "tickets" contains null values
```



This is unsafe because existing rows have no way to obtain the new reference automatically after the old reference has already been removed.

It would also immediately break application versions that still read or write `tickets.product_code`.

The database was reset before continuing.

---

# 3. Expansion migration

`030_expand_product_identity.sql` was applied successfully.

The migration:

- added `products.id uuid`;
- assigned UUIDs to the two existing products;
- added a UUID default for future products;
- made `products.id` required;
- added a unique constraint on `products.id`;
- added nullable `tickets.product_id`;
- added `tickets_product_id_fk` as a `NOT VALID` foreign key;
- retained `tickets.product_code`.

The migration completed successfully and assigned IDs to two existing products.

At this stage:

```text
products.code         -> existing business code
products.id           -> new stable identity

tickets.product_code  -> existing reference, still required
tickets.product_id    -> new nullable reference
```

This intermediate state is intentional because old application versions must continue to work while the rollout is in progress.

---

# 4. Mixed-version compatibility

The expansion phase was tested again on a clean database before running the backfill.

## Old reader

The old reader still worked after the expansion and returned the three original tickets using `product_code`.

This demonstrates that adding `product_id` did not break the old read contract.

## Old writer

The old writer successfully inserted a ticket while supplying only `product_code`.

```text
INSERT 0 1
```

This demonstrates that old application instances can continue writing during the expansion phase.

## Transitional new reader

Before backfill, the original tickets and the old-writer ticket still had a null stored `product_id`.

The new reader nevertheless resolved all of them by falling back to the product code.

Example:

```text
TICKET-1
product_code       = SINGLE
product_id         = NULL
resolved_product_id = <SINGLE product UUID>
```

This means new readers can be deployed before all existing tickets have been backfilled.

## New dual-reference writer

The new writer inserted:

```text
LAB04-NEW-1
product_code = DAY
product_id   = <DAY product UUID>
price        = 65.00
currency     = DKK
```

The writer derives `product_code` from the product selected by `product_id` rather than trusting an unrelated code from the caller.

The purchase price remains a separate input. It is not copied from the current catalogue price.

---

# 5. Code/ID mismatch test

A deliberate mismatch was created inside a transaction.

`TICKET-1` originally refers to:

```text
product_code = SINGLE
```

Its `product_id` was temporarily changed to the ID belonging to `DAY`.

PostgreSQL accepted the update.

The resulting temporary state was:

```text
TICKET-1
product_code = SINGLE
product_id   = <DAY product UUID>
```

The transaction was then rolled back.

This demonstrates an important distinction:

- the database verifies that `product_code` refers to a real product;
- the database verifies that `product_id` refers to a real product;
- but during the transition it does not verify that both references identify the **same** product.

Therefore the new writer must prevent mismatched pairs while both representations coexist.

---

# 6. Unknown product ID

A ticket was deliberately inserted using:

```text
product_id = 00000000-0000-0000-0000-000000000000
```

PostgreSQL rejected the write:

```text
ERROR: insert or update on table "tickets"
violates foreign key constraint "tickets_product_id_fk"

DETAIL:
Key (product_id)=(00000000-0000-0000-0000-000000000000)
is not present in table "products".
```

This shows that the new foreign key protects against references to nonexistent products.

This is different from the mismatch test: a real product ID is accepted even when paired with the wrong legacy code, but a nonexistent ID is rejected.

---

# 7. Backfill

`031_backfill_ticket_product.sql` contains:

```sql
update tickets t
set product_id = p.id
from products p
where t.product_id is null
  and p.code = t.product_code;
```

The original run produced:

```text
UPDATE 3
```

and the second run produced:

```text
UPDATE 0
```



During the compatibility test, an additional old-style ticket existed. The backfill then produced:

```text
UPDATE 4
```

and another execution again produced:

```text
UPDATE 0
```

This demonstrates that the backfill is repeatable.

It:

- fills only missing IDs;
- does not overwrite IDs already assigned by the new writer;
- can be rerun after late writes from an old application instance.

---

# 8. Verification after backfill

After the backfill, the verification query returned no inconsistent references:

```text
(0 rows)
```

The original ticket data was:

```text
TICKET-1 | SINGLE | <SINGLE UUID> | 36.00 | DKK
TICKET-2 | SINGLE | <SINGLE UUID> | 36.00 | DKK
TICKET-3 | DAY    | <DAY UUID>    | 65.00 | DKK
```



During the later run, the old-style and new-style test tickets were also resolved correctly and verification again returned zero invalid rows.

The historical value of `TICKET-3` remained:

```text
65.00 DKK
```

No ticket price or currency was recalculated from the product catalogue.

---

# 9. Testing the NOT NULL deployment gate

A deliberate old-style ticket was inserted:

```text
LAB04-NULL-PRODUCT-ID
product_code = SINGLE
product_id   = NULL
```



`032_require_ticket_product.sql` was then attempted.

The foreign key validation succeeded, but making `product_id` required failed:

```text
ERROR: column "product_id" of relation "tickets" contains null values
```



This is useful deployment behavior.

The database prevents the contract migration from completing while data from old-only writers remains incomplete.

---

# 10. Repair and successful enforcement

The repeatable backfill was executed again:

```text
UPDATE 1
```

A second execution produced:

```text
UPDATE 0
```



Verification then returned zero bad rows.

`032_require_ticket_product.sql` was executed again and succeeded:

```text
BEGIN
SET
ALTER TABLE
ALTER TABLE
COMMIT
```



At this point:

```text
tickets.product_id
    -> NOT NULL
    -> foreign key to products.id
```

---

# 11. Old writer after product_id became required

The old writer was tested again.

It failed:

```text
ERROR:
null value in column "product_id" of relation "tickets"
violates not-null constraint
```



This establishes the deployment boundary:

> `032_require_ticket_product.sql` must not be deployed while old-only writers are still running.

The database repository alone cannot prove that no old application instances are running. Deployment coordination is therefore required before this step.

---

# 12. Dependency inspection before legacy removal

Before dropping `tickets.product_code`, database dependencies were inspected.

## Views

No views referencing `product_code` were found:

```text
(0 rows)
```

## Functions and procedures

The first dependency query accidentally passed PostgreSQL aggregate functions such as `array_agg` to `pg_get_functiondef()`, which caused an error.

The query was corrected to inspect only ordinary functions and procedures.

The corrected query returned:

```text
(0 rows)
```

The drop was then rehearsed inside a transaction:

```text
BEGIN
SET
(0 rows)
(0 rows)
ALTER TABLE
ROLLBACK
```



This demonstrates that:

- no discovered database view depended on the legacy ticket column;
- no discovered ordinary function/procedure depended on it;
- PostgreSQL could drop the column without `CASCADE`.

The rehearsal was rolled back so the schema remained unchanged until the final contract migration.

---

# 13. Removing tickets.product_code

`033_remove_ticket_product_code.sql` was then executed for real.

Result:

```text
BEGIN
SET
ALTER TABLE
COMMIT
```



The final relationship is therefore:

```text
tickets.product_id -> products.id
```

`products.code` remains in the catalogue and can still be displayed to users or used on price lists.

It is no longer the identity stored on tickets.

---

# 14. Final reader

The final reader joins products through `product_id`:

```sql
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
```

After removing `tickets.product_code`, the reader still returned the original tickets successfully:

```text
TICKET-1 | <SINGLE UUID> | SINGLE | 36.00 | DKK
TICKET-2 | <SINGLE UUID> | SINGLE | 36.00 | DKK
TICKET-3 | <DAY UUID>    | DAY    | 65.00 | DKK
```



The code shown by the reader now comes from `products.code`, not from a legacy column on the ticket.

---

# 15. Final ID-only writer

The final writer no longer writes `tickets.product_code`.

It uses only `product_id` for the product relationship.

The insert succeeded:

```text
INSERT 0 1
```



The newly written ticket was then visible through the final reader:

```text
LAB04-FINAL-1
product = DAY
price   = 65.00
currency = DKK
```



---

# 16. Historical-data verification

The final verification of the three original tickets returned:

```text
TICKET-1 | SINGLE | <SINGLE UUID> | 36.00 | DKK
TICKET-2 | SINGLE | <SINGLE UUID> | 36.00 | DKK
TICKET-3 | DAY    | <DAY UUID>    | 65.00 | DKK
```



This confirms that the migration changed the **identity relationship**, not the commercial history stored on each ticket.

In particular:

```text
TICKET-3 remained 65.00 DKK
```

even though the current product catalogue contains a different DAY price.

---

# 17. Old application after legacy-column removal

The old reader was executed after `tickets.product_code` had been removed.

It failed:

```text
ERROR: column "product_code" does not exist
```

The old writer also failed:

```text
ERROR:
column "product_code" of relation "tickets" does not exist
```



This proves that an old application version is no longer directly compatible after the final contract migration.

---

# Compatibility matrix

| Deployment stage | Old reader | Old writer | Transitional new reader | Dual-reference new writer | Final ID-only reader | Final ID-only writer |
| --- | --- | --- | --- | --- | --- | --- |
| Original schema | Works | Works | Not available | Not available | Not available | Not available |
| After `030` expansion | Works | Works | Works | Works | Possible for reads | Fails because legacy `product_code` is still required |
| After `031` backfill | Works | Works | Works | Works | Works | Fails because legacy `product_code` is still required |
| After `032` requires `product_id` | Works | **Fails** | Works | Works | Works | Fails until legacy column is removed |
| After `033` removes `tickets.product_code` | **Fails** | **Fails** | Fails if it still reads ticket code | No longer needed | Works | Works |

---

# Deployment gates

## Gate 1: deploy expansion

`030_expand_product_identity.sql` is compatible with existing application versions.

Old readers and writers continue to work.

This migration can therefore be deployed before the application transition.

## Gate 2: run the backfill

`031_backfill_ticket_product.sql` can be run while old writers still exist.

Because it updates only rows where `product_id is null`, it is safe to repeat.

The deployment may not proceed to the next gate until verification returns zero missing or mismatched references.

## Gate 3: require product_id

Before running `032_require_ticket_product.sql`:

- the final backfill must have completed;
- verification must return zero invalid rows;
- no old-only writers may still be running;
- new writers must supply `product_id`.

The failed NOT NULL test demonstrated that PostgreSQL protects this gate from incomplete rows.

## Gate 4: remove the legacy column

Before running `033_remove_ticket_product_code.sql`:

- readers must no longer depend on `tickets.product_code`;
- writers must no longer write it;
- database views/functions must be checked;
- application code and tests must be checked separately;
- rollback to an old application contract must no longer be required.

The column must not be dropped using `CASCADE` simply to bypass unknown dependencies.

---

# Rollback considerations

## Before `032`

Returning to the old application is straightforward because `tickets.product_code` is still populated and old readers/writers remain compatible.

`product_id` can effectively be ignored by the old application.

## After `032` but before `033`

Old readers still work because `product_code` remains available.

Old writers do not work because they do not provide the now-required `product_id`.

A rollback to the old application would therefore require either:

- relaxing the `product_id NOT NULL` requirement temporarily; or
- changing the old writer so it also supplies `product_id`.

## After `033`

The old application contract is no longer compatible because `tickets.product_code` no longer exists.

Returning to the old application would require a schema rollback, for example:

1. recreate `tickets.product_code`;
2. repopulate it by joining `tickets.product_id` to `products.id`;
3. restore the appropriate constraint;
4. verify every ticket;
5. only then redeploy the old application.

For this reason, the legacy column should not be removed immediately after the new application is deployed in a real production rollout.

A reasonable production strategy would retain the legacy column for a defined stability period before performing the final contract migration.

---

# Stable product identity

`products.id` is intended to represent immutable product identity.

`products.code` may change for business reasons without changing ticket identity.

The UUID default:

```sql
default gen_random_uuid()
```

assigns IDs to new products, but it does **not** prevent existing IDs from being updated.

Immutability therefore still requires an explicit policy, such as:

- application code never updating product IDs;
- database permissions that do not allow ordinary application roles to modify the identity column;
- optionally additional database protection if the domain requires it.

---

# Migration-tool comparison

## Status

Not completed yet.

This starter repository does not currently use EF Core migrations.

The lab therefore permits comparing the hand-written SQL rollout with an AI-drafted EF Core migration for the same model change.

The comparison should specifically inspect:

- whether `product_id` is initially nullable;
- when it becomes required;
- creation and validation of the foreign key;
- how existing rows are backfilled;
- preservation of historical ticket prices and currencies;
- removal of `tickets.product_code`;
- destructive operations;
- whether generated migration SQL understands the mixed-version rollout automatically.

The key question is not whether an ORM can generate DDL.

The key question is which parts require knowledge of:

- existing production data;
- application-version overlap;
- deployment order;
- safe backfill;
- deployment gates;
- rollback compatibility.

---

# Final decision

The stable `product_id` should become the authoritative relationship between tickets and products.

The rollout must not be performed as a single destructive schema migration.

The demonstrated safe sequence is:

```text
Expand
  ↓
Deploy compatible readers/writers
  ↓
Backfill
  ↓
Verify
  ↓
Stop old writers
  ↓
Require product_id
  ↓
Deploy ID-only code
  ↓
Check dependencies
  ↓
Remove tickets.product_code
```

The tests showed why each stage exists:

- immediate replacement fails on existing data;
- expansion preserves compatibility;
- new readers can tolerate incomplete backfill;
- repeatable backfill handles late old-style writes;
- the FK rejects nonexistent product IDs;
- the transitional schema does not itself prevent a valid code/ID mismatch;
- `NOT NULL` prevents contracting while incomplete rows remain;
- old writers stop working once the new reference becomes required;
- old readers and writers stop working once the legacy column is removed;
- final ID-only readers and writers work correctly;
- historical ticket prices remain unchanged.

Therefore deployment should proceed based on verified compatibility and data state, not merely on whether the migration SQL can execute successfully.
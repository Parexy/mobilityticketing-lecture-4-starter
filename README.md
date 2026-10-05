# MobilityTicketing: Lecture 4 starter

Give products stable IDs without breaking existing tickets or the application code that still uses product codes.

You need Docker Desktop with Compose. Start the database from this directory:

```bash
docker compose up -d
docker compose ps
```

Connect at `localhost:5432` with database, user and password `mobility`. Stop other lecture containers first if they use the same port.

Read [the lab](docs/lab.md) for the tasks and commands. You will find:

- the starting schema and data in `database/postgres/init/`;
- migration examples to complete in `database/postgres/migrations/`;
- queries, inserts and experiments in `database/postgres/experiments/lecture04/`.

The database contains three tickets covering two products. One DAY ticket was bought for 65 DKK; the catalogue now lists 80 DKK. Your migration must keep the price paid.

Leave the initialization files unchanged and put your changes in migrations. If you use your own repository, keep your earlier constraints and check for reporting views or functions that depend on the columns you change.

To stop the database:

```bash
docker compose down
```

To discard your lab data and load the starting data again:

```bash
docker compose down -v
docker compose up -d
```
---

# Compulsory Assignment 1

Group member: Lukas Askholm

Submitted commits:  
Lecture 1: `0738ee578f6ac3140a22e743727ee006c3c69aab`  
Lecture 2: `10cab91a871a5009b6b1de74428d0d5aad9ab394`  
Lecture 3: `9bed33127380cb2a60c31bd541e698a8c8eedecb`  
Lecture 4: `46e23836310caf290eda6d58fbda239e3bca83e8`

Setup and reset instructions: [Lecture 1](https://github.com/Parexy/mobilityticketing-lecture-1-starter#start-the-database), [Lecture 2](https://github.com/Parexy/mobilityticketing-lecture-2-starter#start-the-database), [Lecture 3](https://github.com/Parexy/mobilityticketing-lecture-3-starter#start-the-database), [Lecture 4](https://github.com/Parexy/mobilityticketing-lecture-4-starter/blob/product-identity-lab/README.md)

## Where to find the work

Lecture 1: model, workload map and queries: [model, workload map and ER diagram](https://github.com/Parexy/mobilityticketing-lecture-1-starter/blob/main/docs/lab.md), [schema](https://github.com/Parexy/mobilityticketing-lecture-1-starter/blob/main/database/postgres/001_relational_baseline.sql), [queries](https://github.com/Parexy/mobilityticketing-lecture-1-starter/blob/main/database/postgres/003_queries.sql)

Lecture 2: constraints and tests: [integrity map](https://github.com/Parexy/mobilityticketing-lecture-2-starter/blob/main/docs/integrity-map.md), [constraint migration](https://github.com/Parexy/mobilityticketing-lecture-2-starter/blob/main/database/postgres/migrations/011_ticketing_integrity.sql), [successful writes](https://github.com/Parexy/mobilityticketing-lecture-2-starter/blob/main/database/postgres/experiments/constraints_should_pass.sql), [failed writes](https://github.com/Parexy/mobilityticketing-lecture-2-starter/blob/main/database/postgres/experiments/constraints_should_fail.sql)

Lecture 3: reporting experiment and comparison: [reporting analysis and evidence](https://github.com/Parexy/mobilityticketing-lecture-3-starter/blob/main/docs/reporting-analysis.md), [reporting experiment](https://github.com/Parexy/mobilityticketing-lecture-3-starter/blob/main/database/postgres/experiments/reporting_cases.sql), [comparison query](https://github.com/Parexy/mobilityticketing-lecture-3-starter/blob/main/database/postgres/queries/compare_revenue.sql)

Lecture 4: migration stages and verification: [migration evidence](https://github.com/Parexy/mobilityticketing-lecture-4-starter/blob/product-identity-lab/database/postgres/experiments/lecture04/README.md), [expand migration](https://github.com/Parexy/mobilityticketing-lecture-4-starter/blob/product-identity-lab/database/postgres/migrations/030_expand_product_identity.sql), [backfill](https://github.com/Parexy/mobilityticketing-lecture-4-starter/blob/product-identity-lab/database/postgres/migrations/031_backfill_ticket_product.sql), [require product ID](https://github.com/Parexy/mobilityticketing-lecture-4-starter/blob/product-identity-lab/database/postgres/migrations/032_require_ticket_product.sql), [remove legacy reference](https://github.com/Parexy/mobilityticketing-lecture-4-starter/blob/product-identity-lab/database/postgres/migrations/033_remove_ticket_product_code.sql)

## Two decisions worth discussing

### Route-stop identity

I chose `(route_id, stop_sequence)` as the primary key for `route_stops`. The alternative was `(route_id, stop_id)`. This choice allows the same physical stop to occur more than once on a route, which supports routes that loop or revisit a stop. This is shown in the [Lecture 1 model](https://github.com/Parexy/mobilityticketing-lecture-1-starter/blob/main/docs/lab.md) and used by the [ordered-stops query](https://github.com/Parexy/mobilityticketing-lecture-1-starter/blob/main/database/postgres/003_queries.sql).

### Product identity migration

I used an expand-and-contract migration that introduces `product_id` while temporarily keeping `product_code`. The alternative was replacing `product_code` immediately. This approach allows old and new readers and writers to overlap while existing tickets are backfilled and verified before the old reference is removed. The stages and results are recorded in the [Lecture 4 migration evidence](https://github.com/Parexy/mobilityticketing-lecture-4-starter/blob/product-identity-lab/database/postgres/experiments/lecture04/README.md).

## One limitation or open question

The constraint `reserved_seats BETWEEN 0 AND capacity` prevents an individual trip row from storing more reserved seats than its capacity, but it does not guarantee correct behaviour when two purchases happen concurrently.

This limitation is documented in the [Lecture 2 integrity map](https://github.com/Parexy/mobilityticketing-lecture-2-starter/blob/main/docs/integrity-map.md). The next step would be to test transaction-level protection such as an atomic conditional update or row locking under concurrent purchases.

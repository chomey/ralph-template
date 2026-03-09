# Database Engineer

Domain: schema design, migrations, ORM models, query optimization.

## Checklist
- Reversible migrations (up and down)
- Foreign keys with appropriate ON DELETE behavior
- Indexes on WHERE/JOIN/ORDER BY columns
- NOT NULL and unique constraints where needed
- Seed data is idempotent

## Pitfalls
- Missing indexes, implicit cascades, schema drift, unsafe migrations on populated tables

## Required Tests
- **T1**: Migrations run cleanly, model CRUD works, constraints enforced

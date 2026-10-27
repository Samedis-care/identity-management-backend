# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Identity Management (IM) API — a custom IAM system providing authentication and authorization for multiple applications and tenants. Built with Rails 8.1 + MongoDB (Mongoid) + Devise + Doorkeeper OAuth2.

## Common Commands

```bash
# Tests
bundle exec rspec                          # Run all tests
bundle exec rspec spec/path/to/spec.rb     # Run a single spec file

# Linting
bundle exec rubocop                        # Lint Ruby code
bundle exec brakeman                       # Security scan

# Database
rails db:migrate
rails db:mongoid:create_indexes
rails db:mongoid:remove_undefined_indexes
manual=true rails db:seed                  # Seed requires explicit flag

# OpenAPI docs
rails generate openapi_spec <route_name> -f   # (Re-)generate one route's path file under spec/openapi/
rails "openapi_spec:combine"                  # Rebuild public/api-docs/v1/*.yaml from the path files and serializer schemas
rails "openapi_spec:api[v1]"                  # Regenerate every route, then combine (the Docker build runs this)

# App management (one-time setup)
rails app:register name="my-app" url="https://domain.local"
rails app:admin name="my-app" email="admin@domain.local"
```

### Local test setup

`bundle exec rspec` needs this first. No GitHub workflow runs the suite, so nothing else catches a failure.

- `config/mongoid.yml` and `config/application.yml` are gitignored. Copy them from their `.example` files. `mongoid.yml.example` has no `test:` section, so add one with its own database.
- With `SHRINE_STORAGE: local`, the `FILES_DIRECTORY` must exist, or boot raises.
- Leave `CSP_HEADER` and `CSP_REPORT_ONLY_HEADER` unset. The header middleware in `config/application.rb` reads `env['REQUEST_PATH']`, which rack-test doesn't set, so every `type: :request` spec fails.
- mongod must run as replica set `rs0`.
- Set `CI=1` to eager-load the app (`config/environments/test.rb`), so specs that walk `descendants` see every class.
- `0 examples, 0 failures, N errors occurred outside of examples` means boot failed. It is not a green run.

## Architecture

### Actor Hierarchy

The core data model is a tree of **Actors** using `mongoid-tree`. Every entity (user, app, tenant, group, OU) is an Actor node. Types: `user`, `app`, `tenant`, `group`, `organization`, `ou`, `mapping`, `container`, `enterprise`.

Role inheritance flows up/down the tree via **mappings** (up to 10 nesting levels). This means querying "what roles does a user have?" requires traversing the actor tree.

### Authorization Model

- **Functionalities** (candos): atomic permission strings per app
- **Roles**: named sets of functionalities
- **Groups**: collections of users; groups get roles assigned
- **OU tree**: per-tenant organizational unit hierarchy; OU membership determines group/role access

Admin hierarchy: global admin → app admin → tenant admin.

### Multi-Tenancy

Each **App** defines its own OU tree template, roles, and functionalities (defined in YAML under `config/apps/[app-name]/`). Each **Tenant** is an isolated data silo under an App. App and Tenant configurations are seeded from these YAML files and updated via `ensure_defaults!`.

### API

RESTful JSON:API under `/api/v1/`. Serialized with `jsonapi-serializer`. Authentication uses Doorkeeper OAuth2 tokens (30-day expiry).

OpenAPI docs come from two sources: each serializer's `Schema` class (the components) and the per-route path files under `spec/openapi/{internal,public}/paths/`. `openapi_spec:combine` merges them into the published bundles `public/api-docs/v1/internal.yaml` and `public.yaml`, which are committed. After changing a serializer schema or a route, regenerate and commit the bundles instead of editing them by hand.

### File Uploads

Shrine gem with AWS S3 primary storage, local filesystem cache. A `MaintenanceStorage` wrapper enables graceful degradation when maintenance mode is active.

### Key Conventions

- **Mongoid only** — no SQL database. MongoDB must run in replica set mode (`rs0`).
- **Manual seed flag** — `db:seed` is a no-op without `manual=true` (lowercase, `db/seeds.rb`) to prevent accidental data loss.
- **Per-app YAML configs** — app roles, functionalities, OU templates, and email templates live in `config/apps/[app-name]/`. Migrations for per-app data go in `config/apps/[app-name]/migrate/`.
- **Memory tuning** — jemalloc, YJIT, explicit full GC once per hour via Puma's `out_of_band` handler, and heap dumps to S3 every 10 minutes when `HEAP_DUMPING=true`.
- **Maintenance mode** — `lib/maintenance_mode.rb` polls `MAINTENANCE_STATE_URL` every 30 s (started from the Puma config). While it is active, `MaintenanceModeReadOnlyConcern`, mixed into every `Mongoid::Document`, raises `MaintenanceMode::ReadOnlyMaintenanceError` on writes, and `MaintenanceStorage` guards file storage.

### Migrations

The migration path is set in `config/application.rb`:

- `db/migrate/` and `config/apps/*/migrate/` run with every `rails db:migrate`.
- `db/migrate/indexes/` holds index migrations. They also run with a plain `db:migrate`, because the migrator globs each path recursively. `INDEXES=true rails db:migrate` limits the run to them.
- `db/migrate_manual/` holds one-off data repairs. It is on the path only with `MANUAL=true` (uppercase; `manual=true` silently skips it). Run one with `MANUAL=true VERSION=<version> rails db:migrate:up`, not `db:migrate`, which would first apply every pending regular migration.
- On-prem installations run `MANUAL=true rails db:migrate` on update. A manual migration must therefore do nothing, and log why, when its operator inputs are missing. The version is then recorded as applied, and `db:migrate:up` silently skips a recorded version. The header of `db/migrate_manual/20261014140000_remove_orphaned_auto_join_invites.rb` shows how to handle that.
- Don't set `INDEXES` and `MANUAL` together: `db/migrate/` itself then drops out of the path.

### Directory Layout

- `app/models/actors/` — Actor subclasses (App, Tenant, Group, Ou, User, etc.)
- `app/controllers/api/v1/` — API controllers
- `app/serializers/` — jsonapi-serializer serializers
- `config/apps/` — per-app YAML seed data, email templates, migrations
- `config/routes/{v1,v1_devise,admin}.rb` — routes, drawn from `config/routes.rb`; auth, social login and confirmations are in `v1_devise.rb`, the `admin/gc_stats` endpoint in `admin.rb`
- `lib/tasks/` — Rake tasks (app management, OpenAPI generation, cleanup). `auto_swagger.rake` is a legacy generator writing to `swagger/v1`; use `openapi_spec` instead
- `spec/` — RSpec tests; `spec/openapi/` holds the per-route OpenAPI sources

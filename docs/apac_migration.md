# APAC Region Split — IMB Runbook (Issue #2336)

Migrates a subset of tenants (and their identities) from the EU cluster
(Frankfurt) onto a **separate, blank APAC IMB cluster** in Singapore, serving
`*.apac.samedis.care`.

> **Datenschutz-No-Go:** No EU tenant identity data may land on the APAC cluster.
> The source cluster is **never mutated** (copy-only) — rollback = do not put the
> APAC backend into service.

This is the IMB half. The SCB half (concept, `region`/`locked`, write-lock via
Cando-stripping) lives in `samedis-care-backend`. **SCB is the source of truth**
for which tenants are APAC; IMB only mirrors the id list.

---

## What changes in IMB

| Piece | Where |
|---|---|
| `region` field on the tenant actor (`nil`/`eu` = EU, `apac` = Singapore) | `app/models/actors/tenant.rb` |
| `apac:*` rake tasks (mark / copy / verify / report_dangling) | `lib/tasks/apac_migration.rake` |
| Migration library (resolver, copier, leak guard, safety registry) | `lib/apac_migration/` |

`region` flows into the SCB-facing view `view_samedis_care_actors` automatically
(the view is `viewOn: 'actors'` with only `$match` stages — no projection), so
SCB sees `region` without any view change.

There is **no routing code** in IMB: EU and APAC IMB are independent deployments;
a user logs in on one or the other. `region` is a marker/selection source, not a
runtime routing input.

---

## Prerequisites

The target cluster **and** target S3 bucket are reached **only via runtime ENV** —
never committed to `config/mongoid.yml` / `application.yml`:

```bash
# MongoDB target — the URI needs only the APAC CLUSTER (no database in the path).
# IMB always writes into the fixed database `identity_management_apac`
# (see ApacMigration::MongoCopier::TARGET_DATABASE), so the same cluster URI can
# be shared via .env with SCB, which pins its own db `samediscare_apac`.
export TARGET_MONGODB_URI="mongodb+srv://<user>:<pass>@<apac-cluster>/?retryWrites=true&w=majority&authSource=admin"
# Optional override for non-prod targets:
# export TARGET_MONGODB_DATABASE="identity_management_apac"

# S3 target (tenant images + user avatars). Source bucket is the app's existing AWS_S3_* config.
export TARGET_S3_BUCKET="samedis-care-imb-apac"
export TARGET_S3_REGION="ap-southeast-1"
export TARGET_S3_ACCESS_KEY_ID="..."
export TARGET_S3_SECRET_ACCESS_KEY="..."
# export TARGET_S3_ENDPOINT="..."   # only for non-AWS / custom endpoints
```

Optional knobs (all tasks): `DRY_RUN=true`, `LIMIT=<n>`, `THREADS=<n>` (default 4),
`BATCH_SIZE=<n>` (default 500), `UPDATED_SINCE=<ISO8601>` (delta copy).

Tenant id input for `mark_region`: `TENANT_IDS="id1,id2,..."` or
`TENANT_IDS_FILE=path/to/ids.txt` (one id per line).

---

## Order of operations

> **Reihenfolge laut Issue: erst SCB markieren, dann dieselben Tenants im IMB.**

### 1. SCB first
On SCB, set `region='apac'` for the migration tenants and export the list:

```ruby
# SCB rails console
File.write('apac_ids.txt', Tenant.apac.pluck(:_id).join("\n"))
```

Copy `apac_ids.txt` to the IMB host.

### 2. Mark the same tenants in IMB

```bash
# dry-run first — check the selection
RAILS_ENV=live bundle exec rake apac:mark_region TENANT_IDS_FILE=apac_ids.txt DRY_RUN=true
# then for real (idempotent — re-running is safe)
RAILS_ENV=live bundle exec rake apac:mark_region TENANT_IDS_FILE=apac_ids.txt
```

### 3. Pre-warm the copy (live, source still mutating — fine)

```bash
RAILS_ENV=live TARGET_MONGODB_URI=... bundle exec rake apac:copy DRY_RUN=true   # verify selection counts
RAILS_ENV=live TARGET_MONGODB_URI=... bundle exec rake apac:copy                # Mongo: full copy
RAILS_ENV=live TARGET_S3_BUCKET=... ... bundle exec rake apac:copy_s3           # S3: images/avatars
RAILS_ENV=live bundle exec rake apac:report_dangling                            # cross-region refs → clarify
RAILS_ENV=live TARGET_MONGODB_URI=... bundle exec rake apac:verify              # completeness + leak guard
```

> `apac:copy_s3` is idempotent (skips keys already on the target) and only ever
> reads keys from already-migrated documents — it can never copy EU objects.
> Re-run it after the delta `apac:copy` so newly-changed images travel too.

### 4. Cutover window (short)

1. SCB locks the APAC tenants (Cando-stripping + cache bust) and pauses writing
   Sidekiq queues. (SCB side.)
2. Delta-finalize IMB:
   ```bash
   RAILS_ENV=live TARGET_MONGODB_URI=... bundle exec rake apac:copy UPDATED_SINCE="<pre-warm start time>"
   RAILS_ENV=live TARGET_S3_BUCKET=... ... bundle exec rake apac:copy_s3   # re-run: new/changed images
   RAILS_ENV=live TARGET_MONGODB_URI=... bundle exec rake apac:verify
   ```
3. Bring up the APAC IMB instance against the APAC cluster (its own
   `config/mongoid.yml` pointing at the APAC cluster) with the new social-login
   client IDs set as ENV (see below). Cut DNS `*.apac.samedis.care`.

### 5. Rollback

Source is untouched → simply do **not** activate the APAC backend; EU stays
authoritative. (SCB unlocks its tenants.)

---

## What gets copied (and what does not)

`apac_ids = Actors::Tenant.apac.pluck(:_id)`

| Set | Selection | Note |
|---|---|---|
| Tenant subtree (`actors`) | `_id ∈ apac_ids` ∪ `parent_ids ∈ apac_ids` | tenants + Organization/Ou/Group/**Mapping**; every Mapping here is APAC by definition |
| Structural ancestors (`actors`) | `parent_ids` of the subtree + user nodes | App + ContainerApps/ContainerTenants/ContainerUsers, **id-preserving** — needed so the tree, paths and roles' `actors_app_id` resolve. App skeleton/config only, no tenant identity, no sibling tenants. |
| App definitions (`actors`) | `_type == Actors::App` (wholesale) | all App nodes incl. the identity-management base app; skeleton/config only |
| System records | MDM tenant (`samedis-care`, region nil) + `global_admin` (User **and** Actors::User) | always copied regardless of region — required on every cluster. The MDM subtree brings the master-data structure and global_admin's MDM-scoped mappings. |
| User identities (`users`) | users with ≥1 APAC mapping | identity (email/name/pw) travels; **EU cache fields cleared** on copy |
| Actors::User nodes (`actors`) | `actor_id` of migrated users | personal nodes live in the global `user_container` |
| Invites (`invites`) | `tenant_id ∈ apac_ids` | |
| Global reference data | `roles`, `functionalities`, `contents` | no identity data; copied whole so group `role_ids` resolve on target |
| S3 objects (`apac:copy_s3`) | image_data keys of migrated actors + users | tenant logos / actor images + user avatars (Shrine, `uploads/<class>/<id>/...`) |

**Deliberately NOT copied:** `account_activities` (audit/login-IP log, regenerates),
`downloads`, `suppression_lists`/`email_blacklists` (global EU), and **any EU
mapping or reference**.

### Cross-region users (EU **and** APAC)
A user mapped into both regions is copied (their login credential is their own),
but **only their APAC-tenant mappings travel** — because only actors in the APAC
subtree are selected. Their EU mappings stay on EU. The user's EU cache fields
(`tenants_cached`, `tenant_candos_cached*`, `tenant_access_group_ids`) are cleared
on copy and regenerate on first APAC login.

### Safety core
`ApacMigration::CollectionRegistry.assert_complete!` runs before every copy and
**raises** if any `tenant_id`-bearing model is neither classified as copied nor
excluded — so a future tenant-scoped collection cannot silently leak or be
forgotten. After each real copy, `ApacMigration::LeakGuard` asserts on the target
that nothing references an **EU source tenant** (the set of source tenants not in
the APAC set): no Mapping/Invite/Tenant tied to an EU tenant, and no user caching
an EU tenant in `tenants_cached` or as a key of `tenant_access_group_ids` /
`tenant_candos_cached`. Records created natively on the live APAC cluster (absent
from the source) are correctly ignored — see `apac:verify` below.

---

## APAC instance configuration (deployment, not code)

The APAC IMB is a standard deployment of this app pointed at the APAC cluster.
No code differs.

> **Do NOT seed the APAC backend** (no `Actors::App` seed / `app:register` /
> roles seeding). The migration copy is authoritative: it brings the App actor,
> container nodes, roles, functionalities and contents over with their **original
> _ids**. Seeding would create the same entities with **new** _ids, so the copied
> tenants (which reference the EU app/container/role ids) would be orphaned and
> role references would dangle. If the APAC db was already seeded, drop its
> `actors`/`roles`/`functionalities`/`contents` and re-run `apac:copy`.

Configure per the existing schema:

- `config/mongoid.yml` (or env) → APAC cluster URI.
- New social-login client IDs for the APAC app as ENV (`config/application.yml`
  schema is unchanged): `GOOGLE_OAUTH_CLIENT_ID`, `AZURE_APPLICATION_CLIENT_ID`,
  `APPLE_CLIENT_ID`, plus the iOS/Android variants. See the Architecture notes for
  the full list.

---

## Verification checklist

- `bundle exec rspec spec/models/actors/tenant_spec.rb spec/lib/apac_migration`
- `apac:mark_region ... DRY_RUN=true` shows the right selection, writes nothing.
- `apac:copy DRY_RUN=true` selection contains **zero** EU-only tenants/identities.
- After a test copy against a throwaway cluster: `apac:verify` reports every set
  as `OK` (all source docs present; extra native target docs shown as `(+N
  native on target)`) and the leak guard passes; copied users have **empty** EU
  cache fields.
- In SCB: after `mark_region`, `region` is visible in `view_samedis_care_actors`.

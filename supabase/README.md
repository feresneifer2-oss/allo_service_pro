# Supabase backend assets

Everything the app expects from a live Supabase project lives here.

## Tables used by the app

| Table | Written by | Read by | Realtime channel |
|---|---|---|---|
| `profiles` | `ProfileRepository` (own row) | same | — |
| `orders` | `OrdersRepository` | RLS-scoped list | `realtime:public:orders` |
| `messages` | `MessagesRepository` | RLS-scoped list | `realtime:public:messages` |
| `pro_availability` | `ProAvailabilityRepository` (own row) | every authenticated identity | `realtime:public:pro_availability` |

`pro_availability` is the durable craftsman online/offline board that feeds the
dashboard indicator **and** the client-facing cards
(`ProfessionalModel.availableNow`).

## Availability data flow (one value, four hops)

| # | Hop | Code |
|---|---|---|
| 1 | The pro flips the dashboard `Switch` | `ProProfileStore.setAvailability` (flips `isAvailable` in the same frame) |
| 2 | Local durable mirror | SharedPreferences key `pro_availability` (`persistToPrefs` / `loadFromPrefs`) — restores the state before the first frame, with no network |
| 3 | Remote write | `ProAvailabilityRepository.upsertAvailability` (`on conflict (pro_id) do update`) — or, while offline, one re-keyed `QueuedActionType.updateProAvailability` entry replayed by `OfflineQueue` on reconnection |
| 4 | Broadcast + ingest | Postgres change → `realtime:public:pro_availability` → `ProAvailabilityStore.applyRemoteRow` → the client board, the owner's own switch and every card (`ProfessionalsRepository` overlay) repaint in the next frame |

A pro who never toggled has **no row**: absence means "unknown", so the feed
keeps each entry's own default instead of being flipped offline by nobody.
Signing out clears the local cache and the in-memory board, never the row — the
row is a business state, not a session.

## Applying the migrations

The app is local-first: with no credentials (`.env` missing) every Supabase call
site degrades to a logged no-op, so an un-migrated project boots fine — the
availability overlay simply keeps the local/mock values.

```bash
# option 1 — Supabase CLI (recommended, tracks applied migrations)
supabase link --project-ref <project-ref>
supabase db push

# option 2 — SQL editor: paste supabase/migrations/*.sql (the files are idempotent)
```

### After applying

1. Realtime must be enabled for the table — the migration adds
   `pro_availability` to the `supabase_realtime` publication, which requires
   Realtime to be turned on for the project (Dashboard → Database → Replication).
2. Verify the policy board:

   ```sql
   select tablename from pg_publication_tables where pubname = 'supabase_realtime';
   select policyname, cmd from pg_policies where tablename = 'pro_availability';
   ```

3. Two authenticated devices are needed to observe cross-device presence: the
   pro toggles the switch on the dashboard, the client sees the badge/dot flip
   without a refresh.

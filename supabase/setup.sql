-- ============================================================
-- ONE-SHOT SETUP: paste this whole file into Supabase → SQL Editor → Run.
-- (Generated from supabase/migrations/0001 + 0002. Safe to run once on a new project.)
-- ============================================================

-- Evenly ledger schema. Money is stored as bigint minor units (cents).
-- Every expense row has expense_shares rows whose paid/owed sums equal the
-- total; add_expense() writes both atomically and enforces that invariant.

create table public.people (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users (id) on delete set null,
  display_name text not null check (length(display_name) between 1 and 80),
  email text,
  is_placeholder boolean not null default false,
  created_by uuid not null default auth.uid() references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 1 and 80),
  type text not null default 'other' check (type in ('home','trip','couple','other')),
  simplify_debts boolean not null default true,
  default_currency char(3) not null default 'INR',
  created_by uuid not null default auth.uid() references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  person_id uuid not null references public.people (id) on delete cascade,
  primary key (group_id, person_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references public.groups (id) on delete cascade,
  description text not null check (length(description) between 1 and 200),
  total_minor bigint not null check (total_minor >= 0),
  currency char(3) not null,
  category text not null default 'General',
  kind text not null default 'expense' check (kind in ('expense','payment')),
  split_method text not null default 'equal'
    check (split_method in ('equal','exact','percent','shares','adjustment')),
  notes text,
  spent_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users (id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.expense_shares (
  expense_id uuid not null references public.expenses (id) on delete cascade,
  person_id uuid not null references public.people (id),
  paid_minor bigint not null default 0 check (paid_minor >= 0),
  owed_minor bigint not null default 0 check (owed_minor >= 0),
  primary key (expense_id, person_id)
);

create index on public.group_members (person_id);
create index on public.expenses (group_id) where deleted_at is null;
create index on public.expense_shares (person_id);

-- ---------------------------------------------------------------------------
-- Helpers (security definer so RLS policies don't recurse)
-- ---------------------------------------------------------------------------
create or replace function public.my_person_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from people where user_id = auth.uid()
$$;

create or replace function public.is_group_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members
    where group_id = g and person_id = my_person_id()
  )
$$;

create or replace function public.can_see_expense(e uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from expenses x
    where x.id = e and (
      (x.group_id is not null and is_group_member(x.group_id))
      or exists (
        select 1 from expense_shares s
        where s.expense_id = x.id and s.person_id = my_person_id()
      )
    )
  )
$$;

-- Create the caller's own person row on sign-up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into people (user_id, display_name, email, created_by)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    new.email,
    new.id
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Atomic expense creation with balance check.
create or replace function public.add_expense(payload jsonb) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  new_id uuid := coalesce((payload ->> 'id')::uuid, gen_random_uuid());
  total bigint := (payload ->> 'total_minor')::bigint;
  paid_sum bigint;
  owed_sum bigint;
begin
  select coalesce(sum((s ->> 'paid_minor')::bigint), 0),
         coalesce(sum((s ->> 'owed_minor')::bigint), 0)
    into paid_sum, owed_sum
    from jsonb_array_elements(payload -> 'shares') s;
  if paid_sum <> total or owed_sum <> total then
    raise exception 'Unbalanced expense: total %, paid %, owed %',
      total, paid_sum, owed_sum using errcode = 'check_violation';
  end if;

  insert into expenses (id, group_id, description, total_minor, currency,
                        category, kind, split_method, notes, spent_at)
  values (
    new_id,
    (payload ->> 'group_id')::uuid,
    payload ->> 'description',
    total,
    payload ->> 'currency',
    coalesce(payload ->> 'category', 'General'),
    coalesce(payload ->> 'kind', 'expense'),
    coalesce(payload ->> 'split_method', 'equal'),
    payload ->> 'notes',
    coalesce((payload ->> 'spent_at')::timestamptz, now())
  );

  insert into expense_shares (expense_id, person_id, paid_minor, owed_minor)
  select new_id, (s ->> 'person_id')::uuid,
         (s ->> 'paid_minor')::bigint, (s ->> 'owed_minor')::bigint
    from jsonb_array_elements(payload -> 'shares') s;

  return new_id;
end $$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.people enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_shares enable row level security;

create policy people_select on public.people for select using (
  user_id = auth.uid()
  or created_by = auth.uid()
  or exists (
    select 1 from group_members gm
    where gm.person_id = people.id and is_group_member(gm.group_id)
  )
  or exists (
    select 1 from expense_shares s
    where s.person_id = people.id and can_see_expense(s.expense_id)
  )
);
create policy people_insert on public.people for insert
  with check (created_by = auth.uid() and user_id is null);
create policy people_update on public.people for update
  using (user_id = auth.uid() or (created_by = auth.uid() and user_id is null));

create policy groups_select on public.groups for select
  using (created_by = auth.uid() or is_group_member(id));
create policy groups_insert on public.groups for insert
  with check (created_by = auth.uid());
create policy groups_update on public.groups for update
  using (is_group_member(id));

create policy gm_select on public.group_members for select
  using (is_group_member(group_id));
create policy gm_insert on public.group_members for insert with check (
  is_group_member(group_id)
  or exists (select 1 from groups g where g.id = group_id and g.created_by = auth.uid())
);
create policy gm_delete on public.group_members for delete
  using (is_group_member(group_id));

create policy expenses_select on public.expenses for select
  using (can_see_expense(id));
create policy expenses_insert on public.expenses for insert with check (
  created_by = auth.uid()
  and (group_id is null or is_group_member(group_id))
);
create policy expenses_update on public.expenses for update
  using (can_see_expense(id));

create policy shares_select on public.expense_shares for select
  using (can_see_expense(expense_id));
create policy shares_insert on public.expense_shares for insert with check (
  exists (
    select 1 from expenses x
    where x.id = expense_id and x.created_by = auth.uid()
  )
);

-- Realtime: clients refetch when ledger tables change.
alter publication supabase_realtime
  add table public.expenses, public.expense_shares, public.groups, public.group_members;

-- Comments, recurring expenses and receipt storage.
-- Apply after 0001_ledger.sql.

-- ---------------------------------------------------------------------------
-- Google sign-in puts the display name in `full_name`.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into people (user_id, display_name, email, created_by)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(new.email, '@', 1)
    ),
    new.email,
    new.id
  );
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Recurring expenses
-- A template expense has repeat_interval <> 'never'. Occurrence n is
-- spent_at + n * step. Postgres month arithmetic clamps to the month end
-- (Jan 31 + 1 month = Feb 28, + 2 months = Mar 31), matching the app.
-- ---------------------------------------------------------------------------
alter table public.expenses
  add column repeat_interval text not null default 'never'
    check (repeat_interval in ('never','weekly','fortnightly','monthly','yearly')),
  add column repeat_index int not null default 0,
  add column next_repeat_at timestamptz,
  add column recurring_parent_id uuid references public.expenses (id) on delete set null,
  add column occurrence_date date,
  add column receipt_path text;

create unique index expenses_occurrence_unique
  on public.expenses (recurring_parent_id, occurrence_date)
  where recurring_parent_id is not null;

create index expenses_next_repeat_idx
  on public.expenses (next_repeat_at)
  where repeat_interval <> 'never' and deleted_at is null;

create or replace function public.repeat_step(interval_name text) returns interval
language sql immutable as $$
  select case interval_name
    when 'weekly' then interval '7 days'
    when 'fortnightly' then interval '14 days'
    when 'monthly' then interval '1 month'
    when 'yearly' then interval '1 year'
  end
$$;

-- Generates every due occurrence for every template. Idempotent; safe to run
-- from pg_cron and from clients on app start. Returns rows created.
create or replace function public.materialize_recurring_expenses() returns int
language plpgsql security definer set search_path = public as $$
declare
  t record;
  occ timestamptz;
  new_id uuid;
  created int := 0;
begin
  for t in
    select * from expenses
    where repeat_interval <> 'never'
      and deleted_at is null
      and next_repeat_at is not null
      and next_repeat_at <= now()
    for update skip locked
  loop
    loop
      occ := t.spent_at + (t.repeat_index + 1) * repeat_step(t.repeat_interval);
      exit when occ > now();

      insert into expenses (group_id, description, total_minor, currency,
        category, kind, split_method, notes, spent_at, created_by,
        recurring_parent_id, occurrence_date)
      values (t.group_id, t.description, t.total_minor, t.currency,
        t.category, t.kind, t.split_method, t.notes, occ, t.created_by,
        t.id, occ::date)
      on conflict (recurring_parent_id, occurrence_date)
        where recurring_parent_id is not null do nothing
      returning id into new_id;

      if new_id is not null then
        insert into expense_shares (expense_id, person_id, paid_minor, owed_minor)
        select new_id, person_id, paid_minor, owed_minor
          from expense_shares where expense_id = t.id;
        created := created + 1;
      end if;

      t.repeat_index := t.repeat_index + 1;
    end loop;

    update expenses
       set repeat_index = t.repeat_index,
           next_repeat_at = t.spent_at
             + (t.repeat_index + 1) * repeat_step(t.repeat_interval)
     where id = t.id;
  end loop;
  return created;
end $$;

revoke all on function public.materialize_recurring_expenses() from public, anon;
grant execute on function public.materialize_recurring_expenses() to authenticated;

-- add_expense: now accepts repeat_interval and receipt_path.
create or replace function public.add_expense(payload jsonb) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  new_id uuid := coalesce((payload ->> 'id')::uuid, gen_random_uuid());
  total bigint := (payload ->> 'total_minor')::bigint;
  repeat_name text := coalesce(payload ->> 'repeat_interval', 'never');
  spent timestamptz := coalesce((payload ->> 'spent_at')::timestamptz, now());
  paid_sum bigint;
  owed_sum bigint;
begin
  select coalesce(sum((s ->> 'paid_minor')::bigint), 0),
         coalesce(sum((s ->> 'owed_minor')::bigint), 0)
    into paid_sum, owed_sum
    from jsonb_array_elements(payload -> 'shares') s;
  if paid_sum <> total or owed_sum <> total then
    raise exception 'Unbalanced expense: total %, paid %, owed %',
      total, paid_sum, owed_sum using errcode = 'check_violation';
  end if;

  insert into expenses (id, group_id, description, total_minor, currency,
                        category, kind, split_method, notes, spent_at,
                        repeat_interval, next_repeat_at, receipt_path)
  values (
    new_id,
    (payload ->> 'group_id')::uuid,
    payload ->> 'description',
    total,
    payload ->> 'currency',
    coalesce(payload ->> 'category', 'General'),
    coalesce(payload ->> 'kind', 'expense'),
    coalesce(payload ->> 'split_method', 'equal'),
    payload ->> 'notes',
    spent,
    repeat_name,
    case when repeat_name = 'never' then null
         else spent + repeat_step(repeat_name) end,
    payload ->> 'receipt_path'
  );

  insert into expense_shares (expense_id, person_id, paid_minor, owed_minor)
  select new_id, (s ->> 'person_id')::uuid,
         (s ->> 'paid_minor')::bigint, (s ->> 'owed_minor')::bigint
    from jsonb_array_elements(payload -> 'shares') s;

  return new_id;
end $$;

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------
create table public.expense_comments (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses (id) on delete cascade,
  author_id uuid not null default public.my_person_id() references public.people (id),
  content text not null check (length(content) between 1 and 2000),
  comment_type text not null default 'user' check (comment_type in ('user','system')),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on public.expense_comments (expense_id, created_at);

alter table public.expense_comments enable row level security;

create policy comments_select on public.expense_comments for select
  using (can_see_expense(expense_id));
create policy comments_insert on public.expense_comments for insert with check (
  can_see_expense(expense_id)
  and author_id = my_person_id()
  and comment_type = 'user'
);
create policy comments_soft_delete on public.expense_comments for update
  using (author_id = my_person_id());

alter publication supabase_realtime add table public.expense_comments;

-- ---------------------------------------------------------------------------
-- Receipt images: private bucket, files stored under "<auth uid>/<file>".
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 10485760, array['image/jpeg','image/png','image/heic'])
on conflict (id) do nothing;

create policy receipts_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy receipts_read on storage.objects for select to authenticated
  using (
    bucket_id = 'receipts'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1 from public.expenses e
        where e.receipt_path = storage.objects.name
          and public.can_see_expense(e.id)
      )
    )
  );

-- ===========================================================================
-- 0005_invites_delete_groups.sql
-- ===========================================================================
-- Invite codes (friends join a group by code), adding people who aren't on
-- the app yet, and deleting groups. Safe to run more than once.

-- 1. Every group gets a short invite code. Existing groups get one too.
create or replace function public.new_invite_code() returns text
language sql volatile as $$
  -- 8 characters, no look-alikes (0/O, 1/I/L).
  select string_agg(
    substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), ''
  )
  from generate_series(1, 8)
$$;

alter table public.groups
  add column if not exists invite_code text not null unique
  default public.new_invite_code();

-- 2. Join a group with its code. Security definer: the caller can't see the
-- group before joining, so RLS would otherwise hide it.
create or replace function public.join_group(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  g uuid;
  me uuid := my_person_id();
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  select id into g from groups
    where invite_code = upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'));
  if g is null then
    raise exception 'No group with that code' using errcode = 'P0002';
  end if;
  insert into group_members (group_id, person_id) values (g, me)
    on conflict do nothing;
  return g;
end $$;

revoke execute on function public.join_group(text) from anon, public;
grant execute on function public.join_group(text) to authenticated;

-- 3. Any member can delete a group. Expenses, shares, comments and
-- memberships are removed with it (on delete cascade).
drop policy if exists groups_delete on public.groups;
create policy groups_delete on public.groups for delete
  using (is_group_member(id));

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

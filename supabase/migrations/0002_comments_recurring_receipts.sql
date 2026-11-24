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

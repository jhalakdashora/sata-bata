-- Optional for projects created before this change: new groups default to
-- Indian rupees. (The app already sends INR explicitly, so this only matters
-- for rows inserted outside the app.)
alter table public.groups alter column default_currency set default 'INR';

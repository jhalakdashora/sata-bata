-- Runs the recurring-expense generator every hour.
-- Requires the pg_cron extension: Dashboard → Database → Extensions → pg_cron.
-- (The app also calls materialize_recurring_expenses() on start, so recurring
-- expenses still appear without this; the cron job makes them appear on
-- time even when nobody opens the app.)

create extension if not exists pg_cron;

select cron.schedule(
  'materialize-recurring-expenses',
  '5 * * * *',
  $$ select public.materialize_recurring_expenses(); $$
);

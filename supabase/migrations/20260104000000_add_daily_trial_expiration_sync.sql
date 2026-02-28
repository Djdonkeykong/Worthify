-- Daily sync for expired trials that should transition to paid
-- This catches cases where the client-side sync or webhook didn't update is_trial

create or replace function public.sync_expired_trials()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated_count integer;
begin
  -- Update users where:
  -- 1. They have an active subscription
  -- 2. They're still marked as trial
  -- 3. But their subscription expiration is in the past (trial ended)
  -- 4. AND they still have the same product (meaning they converted from trial to paid)
  update public.users
  set is_trial = false,
      updated_at = now()
  where subscription_status = 'active'
    and is_trial = true
    and subscription_expires_at < now()
    and subscription_product_id is not null;

  get diagnostics v_updated_count = row_count;

  if v_updated_count > 0 then
    raise notice 'Updated % users from trial to paid status', v_updated_count;
  end if;
end;
$$;

comment on function public.sync_expired_trials is 'Daily job to sync expired trials that converted to paid subscriptions';

-- Schedule daily sync job at 02:00 UTC (runs after monthly credit reset at 00:00)
do $$
declare
  v_job_id integer;
begin
  -- Check if job already exists
  select jobid into v_job_id
  from cron.job
  where jobname = 'sync-expired-trials-daily';

  -- Remove existing job if found
  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  -- Schedule new job
  perform cron.schedule(
    'sync-expired-trials-daily',
    '0 2 * * *',  -- Every day at 2:00 AM UTC
    'select public.sync_expired_trials();'
  );
end $$;

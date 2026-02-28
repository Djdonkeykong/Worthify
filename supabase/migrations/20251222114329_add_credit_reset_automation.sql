-- Enable pg_cron for monthly credit resets
create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- Calculate the next monthly reset date (start of next month, UTC)
create or replace function public.next_credit_reset_date()
returns timestamptz
language sql
stable
as $$
  select date_trunc('month', now()) + interval '1 month';
$$;

-- Grant initial credits when a user becomes paid (non-trial)
create or replace function public.apply_paid_credits_on_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next_reset timestamptz := public.next_credit_reset_date();
begin
  if new.subscription_status = 'active' and coalesce(new.is_trial, false) = false then
    if tg_op = 'INSERT' then
      if coalesce(new.paid_credits_remaining, 0) <= 0 then
        new.paid_credits_remaining := 100;
      end if;
      if new.credits_reset_date is null then
        new.credits_reset_date := v_next_reset;
      end if;
    elsif tg_op = 'UPDATE' then
      if (old.subscription_status is distinct from new.subscription_status and new.subscription_status = 'active')
          or (coalesce(old.is_trial, false) = true and coalesce(new.is_trial, false) = false) then
        new.paid_credits_remaining := 100;
        new.credits_reset_date := v_next_reset;
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_paid_activation_set_credits on public.users;
create trigger on_paid_activation_set_credits
  before insert or update of subscription_status, is_trial
  on public.users
  for each row
  execute function public.apply_paid_credits_on_activation();

-- Monthly reset for paid users
create or replace function public.reset_paid_credits_monthly()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.users
  set paid_credits_remaining = 100,
      credits_reset_date = public.next_credit_reset_date(),
      updated_at = now()
  where subscription_status = 'active'
    and coalesce(is_trial, false) = false
    and (credits_reset_date is null or credits_reset_date <= date_trunc('month', now()));
end;
$$;

-- Schedule monthly reset job on the first day of each month at 00:00 UTC
do $$
declare
  v_job_id integer;
begin
  select jobid into v_job_id
  from cron.job
  where jobname = 'reset-paid-credits-monthly';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'reset-paid-credits-monthly',
    '0 0 1 * *',
    'select public.reset_paid_credits_monthly();'
  );
end $$;

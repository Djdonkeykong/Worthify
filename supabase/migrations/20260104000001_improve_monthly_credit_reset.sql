-- Improve monthly credit reset to be more robust
-- This updated version:
-- 1. Only resets for truly active non-trial subscriptions
-- 2. Checks expiration date to ensure subscription hasn't expired
-- 3. Provides better logging

create or replace function public.reset_paid_credits_monthly()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated_count integer;
  v_next_reset timestamptz := public.next_credit_reset_date();
begin
  -- Reset credits for users where:
  -- 1. subscription_status = 'active' (currently active)
  -- 2. is_trial = false (not in trial - only paid users)
  -- 3. subscription_expires_at is in the future OR null (subscription still valid)
  -- 4. credits_reset_date is null or has passed (due for reset)
  update public.users
  set paid_credits_remaining = 100,
      credits_reset_date = v_next_reset,
      updated_at = now()
  where subscription_status = 'active'
    and coalesce(is_trial, false) = false
    and (subscription_expires_at is null or subscription_expires_at > now())
    and (credits_reset_date is null or credits_reset_date <= date_trunc('month', now()));

  get diagnostics v_updated_count = row_count;

  if v_updated_count > 0 then
    raise notice 'Reset credits for % paid users. Next reset: %', v_updated_count, v_next_reset;
  else
    raise notice 'No users eligible for credit reset';
  end if;
end;
$$;

comment on function public.reset_paid_credits_monthly is 'Monthly reset of credits for active paid (non-trial) subscriptions. Only resets for users with valid, non-expired subscriptions.';

-- Grant credits for trial users once, and keep monthly resets for paid (non-trial) users only.
create or replace function public.apply_paid_credits_on_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next_reset timestamptz := public.next_credit_reset_date();
begin
  if new.subscription_status = 'active' then
    if tg_op = 'INSERT' then
      if coalesce(new.paid_credits_remaining, 0) <= 0 then
        new.paid_credits_remaining := 100;
      end if;
      if coalesce(new.is_trial, false) = false and new.credits_reset_date is null then
        new.credits_reset_date := v_next_reset;
      end if;
    elsif tg_op = 'UPDATE' then
      if old.subscription_status is distinct from new.subscription_status
          and new.subscription_status = 'active' then
        new.paid_credits_remaining := 100;
      end if;

      if coalesce(old.is_trial, false) = false
          and coalesce(new.is_trial, false) = true then
        if coalesce(new.paid_credits_remaining, 0) <= 0 then
          new.paid_credits_remaining := 100;
        end if;
      end if;

      if coalesce(old.is_trial, false) = true
          and coalesce(new.is_trial, false) = false then
        new.paid_credits_remaining := 100;
      end if;

      if coalesce(new.is_trial, false) = false then
        if new.credits_reset_date is null
            or coalesce(old.is_trial, false) = true
            or old.subscription_status is distinct from new.subscription_status then
          new.credits_reset_date := v_next_reset;
        end if;
      end if;
    end if;
  end if;

  return new;
end;
$$;

-- Migrate subscription fields from RevenueCat to Superwall
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'revenue_cat_user_id'
  ) THEN
    ALTER TABLE public.users RENAME COLUMN revenue_cat_user_id TO billing_user_id;
  END IF;
EXCEPTION
  WHEN duplicate_column THEN
    -- Column already renamed; ignore
    NULL;
END$$;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS subscription_provider TEXT DEFAULT 'superwall';

COMMENT ON COLUMN public.users.billing_user_id IS 'Billing user ID for linking subscriptions (Superwall)';
COMMENT ON COLUMN public.users.subscription_provider IS 'Subscription provider name (e.g., superwall)';

CREATE INDEX IF NOT EXISTS idx_users_billing_user_id ON public.users(billing_user_id);

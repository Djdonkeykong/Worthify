-- Add subscription-related columns to users table
-- This creates a cache of subscription data from RevenueCat
-- RevenueCat remains the source of truth

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'free',
ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS revenue_cat_user_id TEXT,
ADD COLUMN IF NOT EXISTS subscription_product_id TEXT,
ADD COLUMN IF NOT EXISTS is_trial BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS subscription_last_synced_at TIMESTAMP WITH TIME ZONE;

-- Create index for faster subscription queries
CREATE INDEX IF NOT EXISTS idx_users_subscription_status ON public.users(subscription_status);
CREATE INDEX IF NOT EXISTS idx_users_subscription_expires_at ON public.users(subscription_expires_at);
CREATE INDEX IF NOT EXISTS idx_users_revenue_cat_id ON public.users(revenue_cat_user_id);

-- Add comment to document the fields
COMMENT ON COLUMN public.users.subscription_status IS 'Subscription status: free, active, expired, cancelled. Cached from RevenueCat.';
COMMENT ON COLUMN public.users.subscription_expires_at IS 'When the subscription expires. Null for free users.';
COMMENT ON COLUMN public.users.revenue_cat_user_id IS 'RevenueCat user ID for linking subscriptions.';
COMMENT ON COLUMN public.users.subscription_product_id IS 'Product ID from RevenueCat (monthly, yearly, etc).';
COMMENT ON COLUMN public.users.is_trial IS 'Whether user is currently in trial period.';
COMMENT ON COLUMN public.users.subscription_last_synced_at IS 'Last time subscription data was synced from RevenueCat.';

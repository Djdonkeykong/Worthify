-- Add gender and notification preferences to users table
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS gender TEXT,
  ADD COLUMN IF NOT EXISTS notification_enabled BOOLEAN DEFAULT false;

-- Add comment to columns
COMMENT ON COLUMN public.users.gender IS 'User gender preference: male, female, or other';
COMMENT ON COLUMN public.users.notification_enabled IS 'Whether user has enabled push notifications';

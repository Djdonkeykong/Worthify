-- Add notification preference columns to users table
-- Run this in Supabase SQL Editor

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS upload_reminders_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS promotions_enabled BOOLEAN DEFAULT false;

-- Add comment for documentation
COMMENT ON COLUMN public.users.upload_reminders_enabled IS 'User preference for upload reminder notifications';
COMMENT ON COLUMN public.users.promotions_enabled IS 'User preference for promotional notifications';

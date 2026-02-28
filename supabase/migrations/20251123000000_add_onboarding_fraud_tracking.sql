-- Add onboarding and fraud tracking fields to users table
-- This migration adds comprehensive state management for the onboarding flow
-- and fraud prevention through device fingerprinting

-- Onboarding state tracking
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS onboarding_state TEXT DEFAULT 'not_started'
  CHECK (onboarding_state IN ('not_started', 'in_progress', 'payment_complete', 'completed')),
ADD COLUMN IF NOT EXISTS onboarding_checkpoint TEXT,
ADD COLUMN IF NOT EXISTS payment_completed_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS onboarding_started_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS onboarding_version INTEGER DEFAULT 1;

-- User preferences for feed filtering
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS preferred_gender_filter TEXT DEFAULT 'all'
  CHECK (preferred_gender_filter IN ('men', 'women', 'all'));

-- Fraud prevention
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS device_fingerprint TEXT,
ADD COLUMN IF NOT EXISTS fraud_score INTEGER DEFAULT 0
  CHECK (fraud_score >= 0 AND fraud_score <= 100),
ADD COLUMN IF NOT EXISTS fraud_flags JSONB DEFAULT '[]'::jsonb;

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_users_onboarding_state ON public.users(onboarding_state);
CREATE INDEX IF NOT EXISTS idx_users_onboarding_completed ON public.users(onboarding_completed);
CREATE INDEX IF NOT EXISTS idx_users_device_fingerprint ON public.users(device_fingerprint);
CREATE INDEX IF NOT EXISTS idx_users_preferred_gender_filter ON public.users(preferred_gender_filter);

-- Trial history tracking table for fraud prevention
CREATE TABLE IF NOT EXISTS public.trial_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  device_fingerprint TEXT NOT NULL,
  started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expired_at TIMESTAMP WITH TIME ZONE,
  converted_to_paid BOOLEAN DEFAULT FALSE,
  subscription_product_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on trial_history
ALTER TABLE public.trial_history ENABLE ROW LEVEL SECURITY;

-- Create policy for trial_history - users can only view their own trial history
CREATE POLICY "Users can view own trial history"
  ON public.trial_history
  FOR SELECT
  USING (auth.uid() = user_id);

-- Create policy for trial_history - service role can insert/update
CREATE POLICY "Service role can manage trial history"
  ON public.trial_history
  FOR ALL
  USING (auth.role() = 'service_role');

-- Create indexes for trial_history
CREATE INDEX IF NOT EXISTS idx_trial_history_user_id ON public.trial_history(user_id);
CREATE INDEX IF NOT EXISTS idx_trial_history_device_fingerprint ON public.trial_history(device_fingerprint);
CREATE INDEX IF NOT EXISTS idx_trial_history_started_at ON public.trial_history(started_at);

-- Add comments to document the fields
COMMENT ON COLUMN public.users.onboarding_completed IS 'Whether user has completed the full onboarding process';
COMMENT ON COLUMN public.users.onboarding_state IS 'Current onboarding state: not_started, in_progress, payment_complete, completed';
COMMENT ON COLUMN public.users.onboarding_checkpoint IS 'Last onboarding page/step completed (e.g., gender, tutorial, paywall, account, welcome)';
COMMENT ON COLUMN public.users.payment_completed_at IS 'Timestamp when user completed payment during onboarding';
COMMENT ON COLUMN public.users.onboarding_completed_at IS 'Timestamp when user completed the entire onboarding process';
COMMENT ON COLUMN public.users.onboarding_started_at IS 'Timestamp when user first started onboarding';
COMMENT ON COLUMN public.users.onboarding_version IS 'Version of onboarding flow completed (for A/B testing and migrations)';
COMMENT ON COLUMN public.users.preferred_gender_filter IS 'User preference for filtering products by gender: men, women, or all';
COMMENT ON COLUMN public.users.device_fingerprint IS 'Anonymized device fingerprint for fraud detection and trial tracking';
COMMENT ON COLUMN public.users.fraud_score IS 'Calculated fraud risk score (0-100, higher = more suspicious)';
COMMENT ON COLUMN public.users.fraud_flags IS 'JSON array of fraud indicators: rapid_account_creation, disposable_email, multiple_trials, vpn_detected, etc.';

COMMENT ON TABLE public.trial_history IS 'Tracks trial usage by device to prevent abuse through multiple accounts';
COMMENT ON COLUMN public.trial_history.device_fingerprint IS 'Device fingerprint to track trial usage across accounts';
COMMENT ON COLUMN public.trial_history.converted_to_paid IS 'Whether the trial was converted to a paid subscription';

-- Create function to update trial history when user converts to paid
CREATE OR REPLACE FUNCTION public.update_trial_conversion()
RETURNS TRIGGER AS $$
BEGIN
  -- If subscription status changed to active and was previously on trial
  IF NEW.subscription_status = 'active' AND NEW.is_trial = FALSE AND OLD.is_trial = TRUE THEN
    UPDATE public.trial_history
    SET
      converted_to_paid = TRUE,
      expired_at = NOW(),
      subscription_product_id = NEW.subscription_product_id,
      updated_at = NOW()
    WHERE user_id = NEW.id AND converted_to_paid = FALSE;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to track trial conversions
DROP TRIGGER IF EXISTS on_trial_conversion ON public.users;
CREATE TRIGGER on_trial_conversion
  AFTER UPDATE ON public.users
  FOR EACH ROW
  WHEN (OLD.subscription_status IS DISTINCT FROM NEW.subscription_status OR
        OLD.is_trial IS DISTINCT FROM NEW.is_trial)
  EXECUTE FUNCTION public.update_trial_conversion();

-- Add onboarding preference fields to users table
-- These fields capture user preferences during the onboarding flow
-- to personalize their experience and improve recommendation algorithms

ALTER TABLE public.users
-- Style direction - "Which styles do you like?" (multi-select)
ADD COLUMN IF NOT EXISTS style_direction JSONB DEFAULT '[]'::jsonb,

-- What you want - "What are you mostly looking for?" (multi-select)
ADD COLUMN IF NOT EXISTS what_you_want JSONB DEFAULT '[]'::jsonb,

-- Budget - "What price range feels right?" (single select)
ADD COLUMN IF NOT EXISTS budget TEXT
  CHECK (budget IN ('Affordable', 'Mid-range', 'Premium', 'It varies', NULL)),

-- Discovery source (how they found the app)
ADD COLUMN IF NOT EXISTS discovery_source TEXT
  CHECK (discovery_source IN ('instagram', 'tiktok', 'facebook', 'youtube', 'google', 'friendOrFamily', 'other', NULL));

-- Create indexes for commonly queried preference fields
CREATE INDEX IF NOT EXISTS idx_users_budget ON public.users(budget);
CREATE INDEX IF NOT EXISTS idx_users_discovery_source ON public.users(discovery_source);

-- Create GIN indexes for JSONB array fields to enable fast containment queries
CREATE INDEX IF NOT EXISTS idx_users_style_direction_gin ON public.users USING GIN (style_direction);
CREATE INDEX IF NOT EXISTS idx_users_what_you_want_gin ON public.users USING GIN (what_you_want);

-- Add comments to document the fields
COMMENT ON COLUMN public.users.style_direction IS 'JSON array of style directions: ["Streetwear", "Minimal", "Casual", "Classic", "Bold", "Everything"]';
COMMENT ON COLUMN public.users.what_you_want IS 'JSON array of product interests: ["Outfits", "Shoes", "Tops", "Accessories", "Everything"]';
COMMENT ON COLUMN public.users.budget IS 'Budget preference: Affordable, Mid-range, Premium, or It varies';
COMMENT ON COLUMN public.users.discovery_source IS 'How the user discovered the app (for attribution tracking)';

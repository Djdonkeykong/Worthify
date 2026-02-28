-- Create instagram_url_cache table for caching Instagram post URLs and their extracted image URLs
-- This prevents duplicate ScrapingBee API calls (5 credits each) when multiple users share the same post
CREATE TABLE IF NOT EXISTS instagram_url_cache (
    id BIGSERIAL PRIMARY KEY,
    instagram_url TEXT NOT NULL UNIQUE,
    normalized_url TEXT NOT NULL, -- URL without query params for better matching
    image_url TEXT NOT NULL,
    image_width INTEGER,
    image_height INTEGER,
    extraction_method TEXT, -- 'scrapingbee', 'jina', etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_accessed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    access_count INTEGER DEFAULT 1
);

-- Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_instagram_cache_normalized_url ON instagram_url_cache(normalized_url);
CREATE INDEX IF NOT EXISTS idx_instagram_cache_created_at ON instagram_url_cache(created_at);

-- Enable RLS
ALTER TABLE instagram_url_cache ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read cached URLs
CREATE POLICY "Allow authenticated users to read cache"
    ON instagram_url_cache
    FOR SELECT
    TO authenticated
    USING (true);

-- Allow authenticated users to insert new cache entries
CREATE POLICY "Allow authenticated users to insert cache"
    ON instagram_url_cache
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Allow authenticated users to update access tracking
CREATE POLICY "Allow authenticated users to update cache"
    ON instagram_url_cache
    FOR UPDATE
    TO authenticated
    USING (true);

-- Function to update last_accessed_at and increment access_count
CREATE OR REPLACE FUNCTION update_instagram_cache_access()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_accessed_at = NOW();
    NEW.access_count = OLD.access_count + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update access tracking on UPDATE
CREATE TRIGGER instagram_cache_access_trigger
    BEFORE UPDATE ON instagram_url_cache
    FOR EACH ROW
    EXECUTE FUNCTION update_instagram_cache_access();

-- Optional: Function to clean up old cache entries (older than 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_instagram_cache()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM instagram_url_cache
    WHERE created_at < NOW() - INTERVAL '30 days'
    AND last_accessed_at < NOW() - INTERVAL '30 days';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

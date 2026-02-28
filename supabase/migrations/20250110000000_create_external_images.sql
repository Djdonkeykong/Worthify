-- Create external_images table for storing images from Unsplash, Pexels, Pixabay
CREATE TABLE IF NOT EXISTS external_images (
    id BIGSERIAL PRIMARY KEY,
    external_id TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('unsplash', 'pexels', 'pixabay')),
    image_url TEXT NOT NULL,
    thumbnail_url TEXT,
    photographer_name TEXT,
    photographer_url TEXT,
    description TEXT,
    width INTEGER,
    height INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (external_id, source)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_external_images_source ON external_images(source);
CREATE INDEX IF NOT EXISTS idx_external_images_external_id ON external_images(external_id);

-- Add external_image_id to favorites table
ALTER TABLE favorites ADD COLUMN IF NOT EXISTS external_image_id BIGINT REFERENCES external_images(id);

-- Add constraint to ensure either product_id or external_image_id is set
ALTER TABLE favorites DROP CONSTRAINT IF EXISTS favorites_product_or_external_check;
ALTER TABLE favorites ADD CONSTRAINT favorites_product_or_external_check
    CHECK (
        (product_id IS NOT NULL AND external_image_id IS NULL) OR
        (product_id IS NULL AND external_image_id IS NOT NULL)
    );

-- Create index for favorites with external images
CREATE INDEX IF NOT EXISTS idx_favorites_external_image ON favorites(external_image_id) WHERE external_image_id IS NOT NULL;

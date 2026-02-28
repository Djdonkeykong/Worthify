-- Enable RLS on detected_items table
ALTER TABLE detected_items ENABLE ROW LEVEL SECURITY;

-- Allow public read access to detected_items
DROP POLICY IF EXISTS "Allow public read access" ON detected_items;
CREATE POLICY "Allow public read access"
ON detected_items FOR SELECT
TO anon, authenticated
USING (true);

-- Optional: Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_detected_items_product_id ON detected_items(product_id);

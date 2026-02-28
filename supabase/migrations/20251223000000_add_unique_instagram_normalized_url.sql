-- Ensure normalized Instagram URLs are unique for reliable upserts.
-- This enables cross-user cache reuse even with query params.

WITH ranked AS (
    SELECT
        id,
        normalized_url,
        ROW_NUMBER() OVER (
            PARTITION BY normalized_url
            ORDER BY last_accessed_at DESC NULLS LAST,
                     created_at DESC NULLS LAST,
                     id DESC
        ) AS rn
    FROM instagram_url_cache
)
DELETE FROM instagram_url_cache
USING ranked
WHERE instagram_url_cache.id = ranked.id
  AND ranked.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS instagram_url_cache_normalized_url_key
    ON instagram_url_cache (normalized_url);

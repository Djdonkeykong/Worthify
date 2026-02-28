-- Add DELETE policy for user_searches table
-- This allows users to delete their own search history entries

CREATE POLICY "Users can delete own searches"
    ON user_searches FOR DELETE
    USING (auth.uid() = user_id);

-- Update deduct_credits function to deduct available credits even if insufficient
-- Instead of failing when user has fewer credits than garments detected,
-- just deduct whatever credits they have remaining

CREATE OR REPLACE FUNCTION deduct_credits(
  p_user_id UUID,
  p_garment_count INTEGER
)
RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  paid_credits_remaining INTEGER,
  subscription_status TEXT
) AS $$
DECLARE
  v_subscription_status TEXT;
  v_paid_credits INTEGER;
  v_credits_to_deduct INTEGER;
BEGIN
  -- Get current user status
  SELECT
    users.subscription_status,
    users.paid_credits_remaining
  INTO
    v_subscription_status,
    v_paid_credits
  FROM users
  WHERE id = p_user_id;

  -- Check if user exists
  IF NOT FOUND THEN
    RETURN QUERY SELECT
      false AS success,
      'User not found'::TEXT AS message,
      0 AS paid_credits_remaining,
      'active'::TEXT AS subscription_status;
    RETURN;
  END IF;

  -- Calculate credits to deduct (minimum of available credits and garment count)
  v_credits_to_deduct := LEAST(v_paid_credits, p_garment_count);

  -- Deduct available credits
  v_paid_credits := v_paid_credits - v_credits_to_deduct;

  -- Update user record
  UPDATE users
  SET
    paid_credits_remaining = v_paid_credits,
    total_analyses_performed = total_analyses_performed + 1,
    updated_at = NOW()
  WHERE id = p_user_id;

  RETURN QUERY SELECT
    true AS success,
    format('Deducted %s credits', v_credits_to_deduct)::TEXT AS message,
    v_paid_credits AS paid_credits_remaining,
    v_subscription_status AS subscription_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Comment explaining the updated function
COMMENT ON FUNCTION deduct_credits IS 'Deducts credits based on garment count. Deducts available credits even if less than requested (graceful degradation).';

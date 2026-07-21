-- ============================================================
-- AquaFlow COD Settlement System — Database Migration
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Create the cod_settlements table
CREATE TABLE IF NOT EXISTS cod_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
  vendor_id UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  code VARCHAR(6) NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'verified', 'expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  verified_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_cod_settlements_rider ON cod_settlements(rider_id, status);
CREATE INDEX IF NOT EXISTS idx_cod_settlements_vendor ON cod_settlements(vendor_id, status);
CREATE INDEX IF NOT EXISTS idx_cod_settlements_code ON cod_settlements(code) WHERE status = 'pending';

-- 2. RLS Policies
ALTER TABLE cod_settlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Riders can view their own settlements"
  ON cod_settlements FOR SELECT
  USING (rider_id IN (SELECT id FROM riders WHERE profile_id = auth.uid()));

CREATE POLICY "Vendors can view settlements for their business"
  ON cod_settlements FOR SELECT
  USING (vendor_id IN (SELECT id FROM vendors WHERE owner_id = auth.uid()));

-- 3. RPC: generate_cod_settlement
CREATE OR REPLACE FUNCTION generate_cod_settlement(
  p_rider_id UUID,
  p_vendor_id UUID,
  p_amount NUMERIC
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_outstanding NUMERIC;
  v_code VARCHAR(6);
  v_settlement_id UUID;
BEGIN
  -- Expire old pending settlements first
  UPDATE cod_settlements
  SET status = 'expired'
  WHERE status = 'pending' AND expires_at < now();

  -- Calculate outstanding balance:
  -- Total COD delivered orders - (verified + pending settlements)
  SELECT
    COALESCE(
      (SELECT SUM(o.total_amount) FROM orders o
       WHERE o.rider_id = p_rider_id
         AND o.vendor_id = p_vendor_id
         AND o.payment_method = 'cod'
         AND o.status IN ('delivered', 'completed')),
      0
    )
    -
    COALESCE(
      (SELECT SUM(s.amount) FROM cod_settlements s
       WHERE s.rider_id = p_rider_id
         AND s.vendor_id = p_vendor_id
         AND s.status IN ('pending', 'verified')),
      0
    )
  INTO v_outstanding;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  IF p_amount > v_outstanding THEN
    RAISE EXCEPTION 'Amount (%) exceeds outstanding balance (%)', p_amount, v_outstanding;
  END IF;

  -- Generate unique 6-digit numeric code
  LOOP
    v_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM cod_settlements WHERE code = v_code AND status = 'pending'
    );
  END LOOP;

  INSERT INTO cod_settlements (rider_id, vendor_id, amount, code)
  VALUES (p_rider_id, p_vendor_id, p_amount, v_code)
  RETURNING id INTO v_settlement_id;

  RETURN json_build_object(
    'id', v_settlement_id,
    'code', v_code,
    'amount', p_amount,
    'outstanding_after', v_outstanding - p_amount
  );
END;
$$;

-- 4. RPC: verify_cod_settlement
CREATE OR REPLACE FUNCTION verify_cod_settlement(
  p_code VARCHAR,
  p_vendor_id UUID
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_settlement cod_settlements%ROWTYPE;
  v_rider_name TEXT;
  v_outstanding_before NUMERIC;
BEGIN
  -- Expire old pending settlements
  UPDATE cod_settlements
  SET status = 'expired'
  WHERE status = 'pending' AND expires_at < now();

  -- Find settlement by code
  SELECT * INTO v_settlement
  FROM cod_settlements
  WHERE code = p_code AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired settlement code';
  END IF;

  IF v_settlement.vendor_id != p_vendor_id THEN
    RAISE EXCEPTION 'This settlement code does not belong to your business';
  END IF;

  -- Get rider name
  SELECT p.full_name INTO v_rider_name
  FROM riders r JOIN profiles p ON r.profile_id = p.id
  WHERE r.id = v_settlement.rider_id;

  -- Calculate outstanding balance before this verification
  SELECT
    COALESCE(
      (SELECT SUM(o.total_amount) FROM orders o
       WHERE o.rider_id = v_settlement.rider_id
         AND o.vendor_id = p_vendor_id
         AND o.payment_method = 'cod'
         AND o.status IN ('delivered', 'completed')),
      0
    )
    -
    COALESCE(
      (SELECT SUM(s.amount) FROM cod_settlements s
       WHERE s.rider_id = v_settlement.rider_id
         AND s.vendor_id = p_vendor_id
         AND s.status = 'verified'),
      0
    )
  INTO v_outstanding_before;

  -- Mark as verified
  UPDATE cod_settlements
  SET status = 'verified', verified_at = now()
  WHERE id = v_settlement.id;

  RETURN json_build_object(
    'settlement_id', v_settlement.id,
    'rider_name', COALESCE(v_rider_name, 'Unknown Rider'),
    'amount', v_settlement.amount,
    'created_at', v_settlement.created_at,
    'outstanding_before', v_outstanding_before,
    'outstanding_after', v_outstanding_before - v_settlement.amount
  );
END;
$$;

-- 5. RPC: get_rider_cod_balance
CREATE OR REPLACE FUNCTION get_rider_cod_balance(
  p_rider_id UUID,
  p_vendor_id UUID
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_collected NUMERIC;
  v_total_verified NUMERIC;
  v_total_pending NUMERIC;
  v_outstanding NUMERIC;
BEGIN
  -- Total COD collected (from delivered orders)
  SELECT COALESCE(SUM(o.total_amount), 0)
  INTO v_total_collected
  FROM orders o
  WHERE o.rider_id = p_rider_id
    AND o.vendor_id = p_vendor_id
    AND o.payment_method = 'cod'
    AND o.status IN ('delivered', 'completed');

  -- Total verified settlements
  SELECT COALESCE(SUM(s.amount), 0)
  INTO v_total_verified
  FROM cod_settlements s
  WHERE s.rider_id = p_rider_id
    AND s.vendor_id = p_vendor_id
    AND s.status = 'verified';

  -- Total pending settlements
  SELECT COALESCE(SUM(s.amount), 0)
  INTO v_total_pending
  FROM cod_settlements s
  WHERE s.rider_id = p_rider_id
    AND s.vendor_id = p_vendor_id
    AND s.status = 'pending'
    AND s.expires_at > now();

  v_outstanding := v_total_collected - v_total_verified - v_total_pending;

  RETURN json_build_object(
    'outstanding', GREATEST(v_outstanding, 0),
    'pending', v_total_pending,
    'total_submitted', v_total_verified + v_total_pending,
    'total_verified', v_total_verified,
    'total_collected', v_total_collected
  );
END;
$$;

-- 6. RPC: get_vendor_cod_summary
CREATE OR REPLACE FUNCTION get_vendor_cod_summary(
  p_vendor_id UUID
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_todays_verified NUMERIC;
  v_total_verified NUMERIC;
  v_pending_count INT;
  v_pending_amount NUMERIC;
  v_today_start TIMESTAMPTZ;
BEGIN
  v_today_start := date_trunc('day', now());

  SELECT COALESCE(SUM(amount), 0)
  INTO v_todays_verified
  FROM cod_settlements
  WHERE vendor_id = p_vendor_id
    AND status = 'verified'
    AND verified_at >= v_today_start;

  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_verified
  FROM cod_settlements
  WHERE vendor_id = p_vendor_id
    AND status = 'verified';

  SELECT COUNT(*), COALESCE(SUM(amount), 0)
  INTO v_pending_count, v_pending_amount
  FROM cod_settlements
  WHERE vendor_id = p_vendor_id
    AND status = 'pending'
    AND expires_at > now();

  RETURN json_build_object(
    'todays_verified', v_todays_verified,
    'total_verified', v_total_verified,
    'pending_count', v_pending_count,
    'pending_amount', v_pending_amount
  );
END;
$$;

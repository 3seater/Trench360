-- ============================================
-- CHAT360 DATABASE SETUP
-- Copy this entire file and paste it into Supabase SQL Editor
-- Then click "Run" (or press Ctrl+Enter)
-- ============================================

-- Clean up any existing objects first
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'party_members') THEN
    DROP TRIGGER IF EXISTS trigger_cleanup_inactive_members ON party_members;
    DROP TRIGGER IF EXISTS update_member_last_seen ON party_members;
  END IF;

  DROP FUNCTION IF EXISTS get_active_members(timestamptz);
  DROP FUNCTION IF EXISTS get_active_members();
  DROP FUNCTION IF EXISTS cleanup_inactive_members();
  DROP FUNCTION IF EXISTS update_last_seen();

  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'party_members') THEN
    DROP INDEX IF EXISTS idx_party_members_active_seen;
    DROP INDEX IF EXISTS idx_party_members_active;
    DROP INDEX IF EXISTS idx_party_members_active_agora_uid;
    DROP INDEX IF EXISTS idx_party_members_agora_uid;
    DROP INDEX IF EXISTS idx_party_members_agora_uid_lookup;
    DROP INDEX IF EXISTS idx_party_members_is_active;
    DROP INDEX IF EXISTS idx_party_members_last_seen;
    DROP INDEX IF EXISTS idx_party_members_deafened_users;
    DROP INDEX IF EXISTS idx_party_members_voice_status;
    DROP INDEX IF EXISTS idx_party_members_active_party;
  END IF;

  DROP TABLE IF EXISTS party_members;
END $$;

-- Create party_members table
CREATE TABLE party_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  avatar text NOT NULL,
  game text NOT NULL,
  muted boolean DEFAULT false,
  is_active boolean DEFAULT true,
  agora_uid bigint NULL,
  voice_status text NOT NULL DEFAULT 'silent',
  deafened_users text[] DEFAULT '{}',
  party_id uuid NOT NULL DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
  last_seen timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);

-- Add constraint for voice status values
ALTER TABLE party_members
ADD CONSTRAINT check_voice_status CHECK (voice_status IN ('silent', 'muted', 'speaking'));

-- Enable Row Level Security
ALTER TABLE party_members ENABLE ROW LEVEL SECURITY;

-- Enable realtime updates
ALTER PUBLICATION supabase_realtime ADD TABLE party_members;

-- Create function to update last_seen timestamp
CREATE FUNCTION update_last_seen()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_seen = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for last_seen updates
CREATE TRIGGER update_member_last_seen
  BEFORE UPDATE ON party_members
  FOR EACH ROW
  EXECUTE FUNCTION update_last_seen();

-- Create function to cleanup inactive members
CREATE FUNCTION cleanup_inactive_members()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_active = false THEN
    NEW.agora_uid = NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for cleanup
CREATE TRIGGER trigger_cleanup_inactive_members
  BEFORE UPDATE OF is_active ON party_members
  FOR EACH ROW
  EXECUTE FUNCTION cleanup_inactive_members();

-- Create public access policies (allows anyone to read/write - for demo purposes)
CREATE POLICY "Allow public read"
  ON party_members FOR SELECT
  USING (true);

CREATE POLICY "Allow public insert"
  ON party_members FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Allow public update"
  ON party_members FOR UPDATE
  USING (true);

CREATE POLICY "Allow public delete"
  ON party_members FOR DELETE
  USING (true);

-- Create indexes for performance
CREATE INDEX idx_party_members_active
ON party_members(is_active)
WHERE is_active = true;

CREATE INDEX idx_party_members_last_seen
ON party_members(last_seen DESC);

CREATE UNIQUE INDEX idx_party_members_active_agora_uid
ON party_members(agora_uid, is_active)
WHERE agora_uid IS NOT NULL AND is_active = true;

CREATE INDEX idx_party_members_deafened_users
ON party_members USING gin(deafened_users);

CREATE INDEX idx_party_members_voice_status
ON party_members(voice_status);

CREATE INDEX idx_party_members_active_party
ON party_members(party_id, is_active)
WHERE is_active = true;

-- Create function to get active members
CREATE FUNCTION get_active_members()
RETURNS TABLE (
  id text,
  name text,
  avatar text,
  game text,
  is_active boolean,
  muted boolean,
  voice_status text,
  deafened_users text[],
  agora_uid bigint,
  party_id uuid,
  last_seen timestamptz,
  created_at timestamptz
) AS $$
BEGIN
  -- Clean up stale members first (inactive for more than 5 minutes)
  UPDATE party_members
  SET is_active = false
  WHERE party_members.is_active = true
  AND party_members.last_seen < NOW() - INTERVAL '5 minutes';

  -- Return active members
  RETURN QUERY
  SELECT
    pm.id::text,
    pm.name,
    pm.avatar,
    pm.game,
    pm.is_active,
    pm.muted,
    pm.voice_status,
    pm.deafened_users,
    pm.agora_uid,
    pm.party_id,
    pm.last_seen,
    pm.created_at
  FROM party_members pm
  WHERE pm.is_active = true
  AND pm.party_id = '11111111-1111-1111-1111-111111111111'::uuid
  ORDER BY pm.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON COLUMN party_members.deafened_users IS 'Array of user IDs that this member has deafened';
COMMENT ON COLUMN party_members.voice_status IS 'Current voice status: silent, muted, or speaking';

-- ============================================
-- SUCCESS! Your database is now set up! 🎮
-- ============================================

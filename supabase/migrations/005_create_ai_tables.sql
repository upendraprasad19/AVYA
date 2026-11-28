-- ============================================================
-- Migration 005: AI & Intelligence Tables
-- ============================================================

-- 1. user_daily_snapshots
CREATE TABLE user_daily_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_date date NOT NULL,
  snapshot_json jsonb NOT NULL,
  created_at timestamptz DEFAULT now(),

  CONSTRAINT user_daily_snapshots_unique_per_day UNIQUE (user_id, snapshot_date)
);

ALTER TABLE user_daily_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_daily_snapshots_select_own" ON user_daily_snapshots FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_daily_snapshots_insert_own" ON user_daily_snapshots FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_daily_snapshots_update_own" ON user_daily_snapshots FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "user_daily_snapshots_delete_own" ON user_daily_snapshots FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_user_daily_snapshots_user_id ON user_daily_snapshots(user_id);
CREATE INDEX idx_user_daily_snapshots_date ON user_daily_snapshots(snapshot_date);

-- 2. ai_coach_interactions
CREATE TABLE ai_coach_interactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_id uuid REFERENCES user_daily_snapshots(id),
  channel text DEFAULT 'app',
  user_message text NOT NULL,
  ai_response text,
  model_used text,
  tokens_used int,
  was_helpful bool,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE ai_coach_interactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_coach_interactions_select_own" ON ai_coach_interactions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "ai_coach_interactions_insert_own" ON ai_coach_interactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "ai_coach_interactions_update_own" ON ai_coach_interactions FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "ai_coach_interactions_delete_own" ON ai_coach_interactions FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_ai_coach_interactions_user_id ON ai_coach_interactions(user_id);
CREATE INDEX idx_ai_coach_interactions_snapshot_id ON ai_coach_interactions(snapshot_id);

CREATE TABLE video_renders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  job_id TEXT UNIQUE NOT NULL,
  video_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  payload JSONB,
  output_url TEXT,
  output_storage_path TEXT,
  file_size_bytes INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ
);

ALTER TABLE video_renders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users own video_renders"
  ON video_renders FOR ALL
  USING (auth.uid() = user_id);

CREATE INDEX idx_video_renders_user_id ON video_renders(user_id);
CREATE INDEX idx_video_renders_job_id ON video_renders(job_id);
CREATE INDEX idx_video_renders_status ON video_renders(status) WHERE status IN ('queued', 'rendering');

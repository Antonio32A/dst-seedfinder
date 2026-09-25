ALTER TABLE users RENAME COLUMN credits TO credit_units;
UPDATE users SET credit_units = 100000;

CREATE TABLE jobs_new (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'done', 'failed', 'cancelled')),
  config TEXT NOT NULL,
  wanted INTEGER NOT NULL,
  max_cost INTEGER NOT NULL CHECK (max_cost >= 0),
  cost INTEGER CHECK (cost BETWEEN 0 AND max_cost),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  result TEXT,
  error TEXT,
  runpod_id TEXT
);

INSERT INTO jobs_new (id, user_id, status, config, wanted, max_cost, cost, created_at, updated_at, result, error, runpod_id)
SELECT id, user_id, status, config, wanted, 0, 0, created_at, updated_at, result, error, runpod_id FROM jobs;

DROP TABLE jobs;
ALTER TABLE jobs_new RENAME TO jobs;

CREATE INDEX jobs_user_id_created_at ON jobs (user_id, created_at DESC);
CREATE INDEX jobs_status ON jobs (status);
CREATE UNIQUE INDEX jobs_runpod_id ON jobs (runpod_id) WHERE runpod_id IS NOT NULL;

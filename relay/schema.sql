CREATE TABLE IF NOT EXISTS inboxes (
  id TEXT PRIMARY KEY,
  read_token_hash TEXT NOT NULL,
  delivery_token_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  inbox_id TEXT NOT NULL,
  envelope TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY (inbox_id) REFERENCES inboxes(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS messages_inbox_created
  ON messages (inbox_id, created_at);
CREATE INDEX IF NOT EXISTS messages_expiry
  ON messages (expires_at);


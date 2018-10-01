return {
  postgres = {
    up = [[
      ALTER TABLE IF EXISTS ONLY "hmacauth_credentials"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';

      ALTER INDEX IF EXISTS "hmacauth_credentials_consumer_id" RENAME TO "hmacauth_credentials_consumer_id_idx";

      -- Unique constraint on "username" already adds btree index
      DROP INDEX IF EXISTS "hmacauth_credentials_username";
    ]],
  },

  cassandra = {
    up = [[
    ]],
  },
}

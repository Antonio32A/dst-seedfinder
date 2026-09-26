DROP INDEX jobs_one_active_per_user;

DELETE FROM jobs WHERE cost IS NOT NULL AND id NOT IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY finished_at DESC) AS latest FROM jobs WHERE cost IS NOT NULL
  )
  WHERE latest <= 3
);

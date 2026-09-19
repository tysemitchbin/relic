-- Removes the 10 test accounts created by seed-test-users.sql, and everything
-- they own (activities, public snapshots, follows, kudos, comments cascade).
delete from auth.users where id::text like 'a0000000-0000-4000-8000-%' and email like 'user%@example.com';

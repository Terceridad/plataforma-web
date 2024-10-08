BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(1);

--- we insert a user into auth.users and return the id into user_id to use
select tests.create_supabase_user('test1');

------------
--- Primary Owner
------------
select tests.authenticate_as('test1');

-- check to see if we can create an accoiunt
select throws_ok(
               $$ insert into saas.tenants (name, personal_tenant) values ('test team', true) $$,
               'new row violates row-level security policy for table "tenants"'
           );

SELECT *
FROM finish();

ROLLBACK;
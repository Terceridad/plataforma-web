/**
  * -------------------------------------------------------
  * Section - tenants
  * -------------------------------------------------------
 */

/**
 * Tenant roles allow you to provide permission levels to users
 * when they're acting on an tenant.  By default, we provide
 * "owner" and "member".  The only distinction is that owners can
 * also manage billing and invite/remove tenant members.
 */
DO
$$
    BEGIN
        -- check it tenant_role already exists on saas schema
        IF NOT EXISTS(SELECT 1
                      FROM pg_type t
                               JOIN pg_namespace n ON n.oid = t.typnamespace
                      WHERE t.typname = 'tenant_role'
                        AND n.nspname = 'saas') THEN
            CREATE TYPE saas.tenant_role AS ENUM ('owner', 'member', 'viewer');
        end if;
    end;
$$;

/**
 * Tenants are the primary grouping for most objects within
 * the system. They have many users, and all billing is connected to
 * an tenant.
 */
CREATE TABLE IF NOT EXISTS saas.tenants
(
    id                    uuid unique                NOT NULL DEFAULT extensions.uuid_generate_v4(),
    -- defaults to the user who creates the tenant
    -- this user cannot be removed from an tenant without changing
    -- the primary owner first
    primary_owner_user_id uuid references auth.users not null default auth.uid(),
    -- Tenant name
    name                  text,
    slug                  text unique,
    personal_tenant      boolean                             default false not null,
    updated_at            timestamp with time zone,
    created_at            timestamp with time zone,
    created_by            uuid references auth.users,
    updated_by            uuid references auth.users,
    metadata      jsonb                               default '{}'::jsonb,
    PRIMARY KEY (id)
);

-- constraint that conditionally allows nulls on the slug ONLY if personal_tenant is true
-- remove this if you want to ignore tenants slugs entirely
ALTER TABLE saas.tenants
    ADD CONSTRAINT saas_tenants_slug_null_if_personal_tenant_true CHECK (
            (personal_tenant = true AND slug is null)
            OR (personal_tenant = false AND slug is not null)
        );

-- Open up access to tenants
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE saas.tenants TO authenticated, service_role;

/**
 * We want to protect some fields on tenants from being updated
 * Specifically the primary owner user id and tenant id.
 * primary_owner_user_id should be updated using the dedicated function
 */
CREATE OR REPLACE FUNCTION saas.protect_tenant_fields()
    RETURNS TRIGGER AS
$$
BEGIN
    IF current_user IN ('authenticated', 'anon') THEN
        -- these are protected fields that users are not allowed to update themselves
        -- platform admins should be VERY careful about updating them as well.
        if NEW.id <> OLD.id
            OR NEW.personal_tenant <> OLD.personal_tenant
            OR NEW.primary_owner_user_id <> OLD.primary_owner_user_id
        THEN
            RAISE EXCEPTION 'You do not have permission to update this field';
        end if;
    end if;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- trigger to protect tenant fields
CREATE TRIGGER saas_protect_tenant_fields
    BEFORE UPDATE
    ON saas.tenants
    FOR EACH ROW
EXECUTE FUNCTION saas.protect_tenant_fields();

-- convert any character in the slug that's not a letter, number, or dash to a dash on insert/update for tenants
CREATE OR REPLACE FUNCTION saas.slugify_tenant_slug()
    RETURNS TRIGGER AS
$$
BEGIN
    if NEW.slug is not null then
        NEW.slug = lower(regexp_replace(NEW.slug, '[^a-zA-Z0-9-]+', '-', 'g'));
    end if;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- trigger to slugify the tenant slug
CREATE TRIGGER saas_slugify_tenant_slug
    BEFORE INSERT OR UPDATE
    ON saas.tenants
    FOR EACH ROW
EXECUTE FUNCTION saas.slugify_tenant_slug();

-- enable RLS for tenants
alter table saas.tenants
    enable row level security;

-- protect the timestamps
CREATE TRIGGER saas_set_tenants_timestamp
    BEFORE INSERT OR UPDATE
    ON saas.tenants
    FOR EACH ROW
EXECUTE PROCEDURE saas.trigger_set_timestamps();

-- set the user tracking
CREATE TRIGGER saas_set_tenants_user_tracking
    BEFORE INSERT OR UPDATE
    ON saas.tenants
    FOR EACH ROW
EXECUTE PROCEDURE saas.trigger_set_user_tracking();

/**
  * Tenant users are the users that are associated with an tenant.
  * They can be invited to join the tenant, and can have different roles.
  * The system does not enforce any permissions for roles, other than restricting
  * billing and tenant membership to only owners
 */
create table if not exists saas.tenant_user
(
    -- id of the user in the tenant
    user_id      uuid references auth.users on delete cascade        not null,
    -- id of the tenant the user is in
    tenant_id   uuid references saas.tenants on delete cascade not null,
    -- role of the user in the tenant
    tenant_role saas.tenant_role                               not null,
    constraint tenant_user_pkey primary key (user_id, tenant_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE saas.tenant_user TO authenticated, service_role;


-- enable RLS for tenant_user
alter table saas.tenant_user
    enable row level security;

/**
* Profiles have the extended data for the users' platform.
*/
create table saas.profiles (
  -- id of the user in the platform
  id uuid not null references auth.users on delete cascade,
  first_name text,
  last_name text,
  -- the path to the image in the storage
  avatar text,

  primary key (id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE saas.profiles TO authenticated, service_role;

alter table saas.profiles enable row level security;

INSERT INTO storage.buckets (id, name)
values
  ('logos', 'logos');

INSERT INTO storage.buckets (id, name)
values
  ('avatars', 'avatars');


/**
  * When an tenant gets created, we want to insert the current user as the first
  * owner
 */
create or replace function saas.add_current_user_to_new_tenant()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
as
$$
begin
    if new.primary_owner_user_id = auth.uid() then
        insert into saas.tenant_user (tenant_id, user_id, tenant_role)
        values (NEW.id, auth.uid(), 'owner');
    end if;
    return NEW;
end;
$$;

-- trigger the function whenever a new tenant is created
CREATE TRIGGER saas_add_current_user_to_new_tenant
    AFTER INSERT
    ON saas.tenants
    FOR EACH ROW
EXECUTE FUNCTION saas.add_current_user_to_new_tenant();

/**
  * When a user signs up, we need to create a personal tenant for them
  * and add them to the tenant_user table so they can act on it
 */
create or replace function saas.run_new_user_setup()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
as
$$
declare
    first_tenant_id    uuid;
    generated_user_name text;
begin

    -- first we setup the user profile
    -- TODO: see if we can get the user's name from the auth.users table once we learn how oauth works
    if new.email IS NOT NULL then
        generated_user_name := split_part(new.email, '@', 1);
    end if;
    -- create the new users's personal tenant
    insert into saas.tenants (name, primary_owner_user_id, personal_tenant, id)
    values (generated_user_name, NEW.id, true, NEW.id)
    returning id into first_tenant_id;

    -- add them to the tenant_user table so they can act on it
    insert into saas.tenant_user (tenant_id, user_id, tenant_role)
    values (first_tenant_id, NEW.id, 'owner');

    insert into saas.profiles (id, first_name, last_name)
    values (NEW.id, NEW.raw_user_meta_data ->> 'first_name', NEW.raw_user_meta_data ->> 'last_name');

    return NEW;
end;
$$;

-- trigger the function every time a user is created
create trigger on_auth_user_created
    after insert
    on auth.users
    for each row
execute procedure saas.run_new_user_setup();

/**
  * -------------------------------------------------------
  * Section - Tenant permission utility functions
  * -------------------------------------------------------
  * These functions are stored on the saas schema, and useful for things like
  * generating RLS policies
 */

/**
  * Returns true if the current user has the pass in role on the passed in tenant
  * If no role is sent, will return true if the user is a member of the tenant
  * NOTE: This is an inefficient function when used on large query sets. You should reach for the get_tenants_with_role and lookup
  * the tenant ID in those cases.
 */
create or replace function saas.has_role_on_tenant(tenant_id uuid, tenant_role saas.tenant_role default null)
    returns boolean
    language sql
    security definer
    set search_path = public
as
$$
select exists(
               select 1
               from saas.tenant_user wu
               where wu.user_id = auth.uid()
                 and wu.tenant_id = has_role_on_tenant.tenant_id
                 and (
                           wu.tenant_role = has_role_on_tenant.tenant_role
                       or has_role_on_tenant.tenant_role is null
                   )
           );
$$;

grant execute on function saas.has_role_on_tenant(uuid, saas.tenant_role) to authenticated;


/**
  * Returns tenant_ids that the current user is a member of. If you pass in a role,
  * it'll only return tenants that the user is a member of with that role.
  */
create or replace function saas.get_tenants_with_role(passed_in_role saas.tenant_role default null)
    returns setof uuid
    language sql
    security definer
    set search_path = public
as
$$
select tenant_id
from saas.tenant_user wu
where wu.user_id = auth.uid()
  and (
            wu.tenant_role = passed_in_role
        or passed_in_role is null
    );
$$;

grant execute on function saas.get_tenants_with_role(saas.tenant_role) to authenticated;

/**
  * Returns tenant_ids that the current user is a member of.
  */
create or replace function saas.get_tenants_for_authenticated_user()
returns setof uuid 
LANGUAGE SQL 
security definer
  SET search_path = PUBLIC stable AS $$
  SELECT tenant_id
  from saas.tenant_user wu
where wu.user_id = auth.uid()
$$;

grant execute on function saas.get_tenants_for_authenticated_user() to authenticated;

/**
  * -------------------------
  * Section - RLS Policies
  * -------------------------
  * This is where we define access to tables in the saas schema
 */

create policy "Avatar images are publicly accessible." on storage.objects
  for select 
  to authenticated
  using (bucket_id = 'avatars');

create policy "Anyone can upload an avatar." on storage.objects
  for insert 
  to authenticated
  with check (bucket_id = 'avatars');

create policy "Anyone can update their own avatar." on storage.objects
  for update 
  to authenticated
  using ( auth.uid() = owner ) with check (bucket_id = 'avatars');

create policy "Logos images are publicly accessible." on storage.objects
  for select 
  to authenticated
  using (bucket_id = 'logos');

create policy "Anyone can upload a logo." on storage.objects
  for insert 
  to authenticated
  with check (bucket_id = 'logos');

create policy "Anyone can update their own logo." on storage.objects
  for update
  to authenticated
  --using ( auth.uid() = owner ) 
  with check (bucket_id = 'logos');
 

create policy "Users can update data to only their records" ON saas.profiles 
    for update
    to authenticated
    with check (
        auth.uid() = profiles.id
    );

create policy "Users can insert their own profile." on saas.profiles
    for insert 
    to authenticated
    with check (
        auth.uid() = profiles.id
    );

create policy "users can view their own tenant_users" on saas.tenant_user
    for select
    to authenticated
    using (
        user_id = auth.uid()
    );

create policy "users can view their teammates" on saas.tenant_user
    for select
    to authenticated
    using (
        saas.has_role_on_tenant(tenant_id) = true
    );

create policy "Tenant users can be deleted by owners except primary tenant owner" on saas.tenant_user
    for delete
    to authenticated
    using (
        (saas.has_role_on_tenant(tenant_id, 'owner') = true)
        AND
        user_id != (select primary_owner_user_id
                    from saas.tenants
                    where tenant_id = tenants.id)
    );

create policy "Tenants are viewable by members" on saas.tenants
    for select
    to authenticated
    using (
    saas.has_role_on_tenant(id) = true
    );

-- Primary owner should always have access to the tenant
create policy "Tenants are viewable by primary owner" on saas.tenants
    for select
    to authenticated
    using (
    primary_owner_user_id = auth.uid()
    );

create policy "Team tenants can be created by any user" on saas.tenants
    for insert
    to authenticated
    with check (personal_tenant = false);


create policy "Tenants can be edited by owners" on saas.tenants
    for update
    to authenticated
    using (
    saas.has_role_on_tenant(id, 'owner') = true
    );

/**
  * -------------------------------------------------------
  * Section - Public functions
  * -------------------------------------------------------
  * Each of these functions exists in the public name space because they are accessible
  * via the API.  it is the primary way developers can interact with saas tenants
 */

/**
* Returns the tenant_id for a given tenant slug
*/

create or replace function public.get_tenant_id(slug text)
    returns uuid
    language sql
as
$$
select id
from saas.tenants
where slug = get_tenant_id.slug;
$$;

grant execute on function public.get_tenant_id(text) to authenticated, service_role;

/**
 * Returns the current user's role within a given tenant_id
*/
create or replace function public.current_user_tenant_role(tenant_id uuid)
    returns jsonb
    language plpgsql
as
$$
DECLARE
    response jsonb;
BEGIN

    select jsonb_build_object(
                   'tenant_role', wu.tenant_role,
                   'is_primary_owner', a.primary_owner_user_id = auth.uid(),
                   'is_personal_tenant', a.personal_tenant
               )
    into response
    from saas.tenant_user wu
             join saas.tenants a on a.id = wu.tenant_id
    where wu.user_id = auth.uid()
      and wu.tenant_id = current_user_tenant_role.tenant_id;

    -- if the user is not a member of the tenant, throw an error
    if response ->> 'tenant_role' IS NULL then
        raise exception 'Not found';
    end if;

    return response;
END
$$;

grant execute on function public.current_user_tenant_role(uuid) to authenticated;

/**
  * Let's you update a users role within an tenant if you are an owner of that tenant
  **/
create or replace function public.update_tenant_user_role(tenant_id uuid, user_id uuid,
                                                           new_tenant_role saas.tenant_role,
                                                           make_primary_owner boolean default false)
    returns void
    security definer
    set search_path = public
    language plpgsql
as
$$
declare
    is_tenant_owner         boolean;
    is_tenant_primary_owner boolean;
    changing_primary_owner   boolean;
begin
    -- check if the user is an owner, and if they are, allow them to update the role
    select saas.has_role_on_tenant(update_tenant_user_role.tenant_id, 'owner') into is_tenant_owner;

    if not is_tenant_owner then
        raise exception 'You must be an owner of the tenant to update a users role';
    end if;

    -- check if the user being changed is the primary owner, if so its not allowed
    select primary_owner_user_id = auth.uid(), primary_owner_user_id = update_tenant_user_role.user_id
    into is_tenant_primary_owner, changing_primary_owner
    from saas.tenants
    where id = update_tenant_user_role.tenant_id;

    if changing_primary_owner = true and is_tenant_primary_owner = false then
        raise exception 'You must be the primary owner of the tenant to change the primary owner';
    end if;

    update saas.tenant_user au
    set tenant_role = new_tenant_role
    where au.tenant_id = update_tenant_user_role.tenant_id
      and au.user_id = update_tenant_user_role.user_id;

    if make_primary_owner = true then
        -- first we see if the current user is the owner, only they can do this
        if is_tenant_primary_owner = false then
            raise exception 'You must be the primary owner of the tenant to change the primary owner';
        end if;

        update saas.tenants
        set primary_owner_user_id = update_tenant_user_role.user_id
        where id = update_tenant_user_role.tenant_id;
    end if;
end;
$$;

grant execute on function public.update_tenant_user_role(uuid, uuid, saas.tenant_role, boolean) to authenticated;

/**
  Returns the current user's tenants
 */
create or replace function public.get_tenants()
    returns json
    language sql
as
$$
select coalesce(json_agg(
                        json_build_object(
                                'tenant_id', wu.tenant_id,
                                'tenant_role', wu.tenant_role,
                                'is_primary_owner', a.primary_owner_user_id = auth.uid(),
                                'username', a.name,    
                                'slug', a.slug,
                                'personal_tenant', a.personal_tenant,
                                'created_at', a.created_at,
                                'updated_at', a.updated_at
                            )
                    ), '[]'::json)
from saas.tenant_user wu
         join saas.tenants a on a.id = wu.tenant_id 
where wu.user_id = auth.uid();
$$;

grant execute on function public.get_tenants() to authenticated;

/**
  Returns a specific tenant that the current user has access to
 */
create or replace function public.get_tenant(tenant_id uuid)
    returns json
    language plpgsql
as
$$
BEGIN
    -- check if the user is a member of the tenant or a service_role user
    if current_user IN ('anon', 'authenticated') and
       (select current_user_tenant_role(get_tenant.tenant_id) ->> 'tenant_role' IS NULL) then
        raise exception 'You must be a member of an tenant to access it';
    end if;


    return (select json_build_object(
                           'tenant_id', a.id,
                           'tenant_role', wu.tenant_role,
                           'is_primary_owner', a.primary_owner_user_id = auth.uid(),
                           'name', a.name,
                           'slug', a.slug,
                           'personal_tenant', a.personal_tenant,
                        --    'billing_enabled', case
                        --                           when a.personal_tenant = true then
                        --                               config.enable_personal_tenant_billing
                        --                           else
                        --                               config.enable_team_tenant_billing
                        --        end,
                        --    'billing_status', bs.status,
                           'created_at', a.created_at,
                           'updated_at', a.updated_at,
                           'metadata', a.metadata
                       )
            from saas.tenants a
                     left join saas.tenant_user wu on a.id = wu.tenant_id and wu.user_id = auth.uid()
                     join saas.config config on true
                    --  left join (select bs.tenant_id, status
                    --             from saas.billing_subscriptions bs
                    --             where bs.tenant_id = get_tenant.tenant_id
                    --             order by created desc
                    --             limit 1) bs on bs.tenant_id = a.id
            where a.id = get_tenant.tenant_id);
END;
$$;

grant execute on function public.get_tenant(uuid) to authenticated, service_role;

/**
  Returns a specific tenant that the current user has access to
 */
create or replace function public.get_tenant_by_slug(slug text)
    returns json
    language plpgsql
as
$$
DECLARE
    internal_tenant_id uuid;
BEGIN
    select a.id
    into internal_tenant_id
    from saas.tenants a
    where a.slug IS NOT NULL
      and a.slug = get_tenant_by_slug.slug;

    return public.get_tenant(internal_tenant_id);
END;
$$;

grant execute on function public.get_tenant_by_slug(text) to authenticated;

/**
  Returns the personal tenant for the current user
 */
create or replace function public.get_personal_tenant()
    returns json
    language plpgsql
as
$$
BEGIN
    return public.get_tenant(auth.uid());
END;
$$;

grant execute on function public.get_personal_tenant() to authenticated;

/**
  * Create an tenant
 */
create or replace function public.create_tenant(slug text default null, name text default null)
    returns json
    language plpgsql
as
$$
DECLARE
    new_tenant_id uuid;
BEGIN
    insert into saas.tenants (slug, name)
    values (create_tenant.slug, create_tenant.name)
    returning id into new_tenant_id;

    return public.get_tenant(new_tenant_id);
EXCEPTION
    WHEN unique_violation THEN
        raise exception 'An tenant with that unique ID already exists';
END;
$$;

grant execute on function public.create_tenant(slug text, name text) to authenticated;

/**
  Update an tenant with passed in info. None of the info is required except for tenant ID.
  If you don't pass in a value for a field, it will not be updated.
  If you set replace_meta to true, the metadata will be replaced with the passed in metadata.
  If you set replace_meta to false, the metadata will be merged with the passed in metadata.
 */
create or replace function public.update_tenant(tenant_id uuid, slug text default null, name text default null,
                                                 metadata jsonb default null,
                                                 replace_metadata boolean default false)
    returns json
    language plpgsql
as
$$
BEGIN

    -- check if postgres role is service_role
    if current_user IN ('anon', 'authenticated') and
       not (select current_user_tenant_role(update_tenant.tenant_id) ->> 'tenant_role' = 'owner') then
        raise exception 'Only tenant owners can update an tenant';
    end if;

    update saas.tenants tenants
    set slug            = coalesce(update_tenant.slug, tenants.slug),
        name            = coalesce(update_tenant.name, tenants.name),
        metadata = case
                              when update_tenant.metadata is null then tenants.metadata -- do nothing
                              when tenants.metadata IS NULL then update_tenant.metadata -- set metadata
                              when update_tenant.replace_metadata
                                  then update_tenant.metadata -- replace metadata
                              else tenants.metadata || update_tenant.metadata end -- merge metadata
    where tenants.id = update_tenant.tenant_id;

    return public.get_tenant(tenant_id);
END;
$$;

grant execute on function public.update_tenant(uuid, text, text, jsonb, boolean) to authenticated, service_role;

/**
  Returns a list of current tenant members. Only tenant owners can access this function.
  It's a security definer because it requries us to lookup personal_tenants for existing members so we can
  get their names.
 */
create or replace function public.get_tenant_members(tenant_id uuid, results_limit integer default 50,
                                                      results_offset integer default 0)
    returns json
    language plpgsql
    security definer
    set search_path = saas
as
$$
BEGIN

    -- only tenant owners can access this function
    if (select public.current_user_tenant_role(get_tenant_members.tenant_id) ->> 'tenant_role' <> 'owner') then
        raise exception 'Only tenant owners can access this function';
    end if;

    return (select json_agg(
                           json_build_object(
                                   'user_id', wu.user_id,
                                   'tenant_role', wu.tenant_role,
                                   'name', p.name,
                                   'firstname', pro.first_name,
                                   'lastname', pro.last_name,
                                   'email', u.email,
                                   'is_primary_owner', a.primary_owner_user_id = wu.user_id
                               )
                       )
            from saas.tenant_user wu
                     join saas.tenants a on a.id = wu.tenant_id
                     join saas.tenants p on p.primary_owner_user_id = wu.user_id and p.personal_tenant = true
                     join auth.users u on u.id = wu.user_id
                     join saas.profiles pro on pro.id = wu.user_id
            where wu.tenant_id = get_tenant_members.tenant_id
            limit coalesce(get_tenant_members.results_limit, 50) offset coalesce(get_tenant_members.results_offset, 0));
END;
$$;

grant execute on function public.get_tenant_members(uuid, integer, integer) to authenticated;

/**
  Allows an owner of the tenant to remove any member other than the primary owner
 */

create or replace function public.remove_tenant_member(tenant_id uuid, user_id uuid)
    returns void
    language plpgsql
as
$$
BEGIN
    -- only tenant owners can access this function
    if saas.has_role_on_tenant(remove_tenant_member.tenant_id, 'owner') <> true then
        raise exception 'Only tenant owners can access this function';
    end if;

    delete
    from saas.tenant_user wu
    where wu.tenant_id = remove_tenant_member.tenant_id
      and wu.user_id = remove_tenant_member.user_id;
END;
$$;

grant execute on function public.remove_tenant_member(uuid, uuid) to authenticated;

create or replace function public.get_all_tenants()
    returns json
    security invoker
    language sql
as
$$

select coalesce(json_agg(
                        json_build_object(
                                'tenant_id', wu.tenant_id,
                                'tenant_role', wu.tenant_role,
                                'is_primary_owner', a.primary_owner_user_id = auth.uid(),
                                'username', a.name,                                                                
                                'firstname', pro.first_name,
                                'lastname', pro.last_name,
                                'slug', a.slug,
                                'personal_tenant', a.personal_tenant,
                                'created_at', a.created_at,
                                'updated_at', a.updated_at
                            )
                    ), '[]'::json)
from saas.tenant_user wu
         join saas.tenants a on a.id = wu.tenant_id                    
         join saas.profiles pro on pro.id = wu.user_id
where auth.role() in ('service_role')
$$;

grant execute on function public.get_all_tenants() to service_role;
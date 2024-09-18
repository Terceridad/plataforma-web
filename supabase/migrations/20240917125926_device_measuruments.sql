
create or replace function public.get_medical_devices_by_tenant(tenant_id uuid, results_limit integer default 50,
                                                      results_offset integer default 0)
    returns json
    language plpgsql
    security definer
as
$$
BEGIN
    return (select json_agg(
                           json_build_object(
                                   'measurement_date', dm.timestamp ,
                                   'last_measurement', concat(dm.measurement_value,' ',dm.unit)  ,
                                   'device_type_name', dt.name
                               )
                       )
            from public.device_measurements dm
                join public.medical_devices md on md.id = dm.medical_device_id 
                join public.device_users du on du.id = dm.device_user_id 
                join public.device_types dt on dt.id = md.device_type
            where du.tenant_id = get_medical_devices_by_tenant.tenant_id
            limit coalesce(get_medical_devices_by_tenant.results_limit, 50) offset coalesce(get_medical_devices_by_tenant.results_offset, 0));
END;
$$;

grant execute on function public.get_medical_devices_by_tenant(uuid, integer, integer) to authenticated, service_role;
{{
    config(
        materialized = "view",
    )
}}

with source_launches as (
    select
        launch_id,
        launch_name,
        last_updated,
        net,
        window_start,
        window_end,
        status_name,
        status_abbrev,
        fail_reason,
        agency_id,
        agency_name,
        agency_type,
        agency_country,
        rocket_id,
        rocket_name,
        mission_name,
        mission_type,
        orbit_name,
        orbit_abbrev,
        pad_id,
        pad_name,
        location_name,
        latitude,
        longitude,
        pad_total_launches
    from {{ source('space_analytics_raw', 'launches') }}
    where launch_id is not null
),

cleaned as (
    select
        nullif(trim(launch_id), '') as launch_id,
        nullif(trim(launch_name), '') as launch_name,
        safe_cast(last_updated as timestamp) as last_updated,
        safe_cast(net as timestamp) as net,
        safe_cast(window_start as timestamp) as window_start,
        safe_cast(window_end as timestamp) as window_end,
        nullif(trim(status_name), '') as status_name,
        nullif(trim(status_abbrev), '') as status_abbrev,
        nullif(trim(fail_reason), '') as fail_reason,
        safe_cast(agency_id as int64) as agency_id,
        nullif(trim(agency_name), '') as agency_name,
        nullif(trim(agency_type), '') as agency_type,
        nullif(trim(agency_country), '') as agency_country,
        safe_cast(rocket_id as int64) as rocket_id,
        nullif(trim(rocket_name), '') as rocket_name,
        nullif(trim(mission_name), '') as mission_name,
        nullif(trim(mission_type), '') as mission_type,
        nullif(trim(orbit_name), '') as orbit_name,
        nullif(trim(orbit_abbrev), '') as orbit_abbrev,
        safe_cast(pad_id as int64) as pad_id,
        nullif(trim(pad_name), '') as pad_name,
        nullif(trim(location_name), '') as location_name,
        safe_cast(latitude as float64) as latitude,
        safe_cast(longitude as float64) as longitude,
        safe_cast(pad_total_launches as int64) as pad_total_launches
    from source_launches
    where nullif(trim(launch_id), '') is not null
    qualify row_number() over (
        partition by nullif(trim(launch_id), '')
        order by safe_cast(last_updated as timestamp) desc nulls last, safe_cast(net as timestamp) desc nulls last
    ) = 1
),

standardized as (
    select
        launch_id,
        launch_name,
        last_updated,
        net,
        window_start,
        window_end,
        date(net) as launch_date,
        extract(year from net) as launch_year,
        format_date('%Y-Q%Q', date(net)) as launch_quarter,
        status_name,
        status_abbrev,
        fail_reason,
        agency_id,
        coalesce(agency_name, 'Unknown') as agency_name,
        coalesce(agency_type, 'Unknown') as agency_type,
        case
            when agency_type = 'Commercial' then 'Commercial'
            when agency_type in ('Government', 'Multinational') then 'Government'
            else 'Other'
        end as agency_sector,
        coalesce(agency_country, 'UNK') as agency_country,
        rocket_id,
        coalesce(rocket_name, 'Unknown') as rocket_name,
        mission_name,
        coalesce(mission_type, 'Unknown') as mission_type,
        orbit_name,
        orbit_abbrev,
        case
            when orbit_abbrev in ('LEO', 'VLEO', 'ISS', 'Sub') then 'LEO'
            when orbit_abbrev = 'SSO' then 'SSO'
            when orbit_abbrev in ('GTO', 'GSO', 'GEO') then 'GTO'
            when orbit_abbrev in ('TLI', 'BLT', 'LLO', 'Helio-N', 'EEO') then 'TLI'
            else 'Other'
        end as orbit_regime,
        pad_id,
        coalesce(pad_name, 'Unknown') as pad_name,
        coalesce(location_name, 'Unknown') as location_name,
        latitude,
        longitude,
        pad_total_launches
    from cleaned
)

select * from standardized

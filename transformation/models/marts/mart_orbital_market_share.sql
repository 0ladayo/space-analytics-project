{{
    config(
        materialized = "table",
        cluster_by = ["orbit_regime", "agency_sector", "agency_country"],
    )
}}

with segment_counts as (
    select
        orbit_regime,
        agency_sector,
        agency_type,
        agency_country,
        mission_type,
        rocket_name,
        count(launch_id) as launch_count,
        countif(status_abbrev = 'Success') as successful_launches,
        countif(is_anomaly) as anomaly_launches
    from {{ ref('int_launches__enriched') }}
    group by
        orbit_regime,
        agency_sector,
        agency_type,
        agency_country,
        mission_type,
        rocket_name
),

with_totals as (
    select
        *,
        sum(launch_count) over (partition by orbit_regime) as orbit_regime_total_launches,
        sum(launch_count) over () as global_total_launches,
        sum(launch_count) over (partition by rocket_name) as vehicle_total_launches
    from segment_counts
)

select
    to_hex(
        md5(
            concat(
                coalesce(orbit_regime, ''), '|',
                coalesce(agency_sector, ''), '|',
                coalesce(agency_type, ''), '|',
                coalesce(agency_country, ''), '|',
                coalesce(mission_type, ''), '|',
                coalesce(rocket_name, '')
            )
        )
    ) as market_segment_key,
    orbit_regime,
    agency_sector,
    agency_type,
    agency_country,
    mission_type,
    rocket_name,
    launch_count,
    successful_launches,
    anomaly_launches,
    orbit_regime_total_launches,
    round(
        100.0 * safe_divide(launch_count, orbit_regime_total_launches),
        2
    ) as share_of_orbit_regime_pct,
    global_total_launches,
    round(
        100.0 * safe_divide(launch_count, global_total_launches),
        2
    ) as share_of_global_orbit_pct,
    vehicle_total_launches,
    round(
        100.0 * safe_divide(vehicle_total_launches, global_total_launches),
        2
    ) as vehicle_global_share_pct
from with_totals

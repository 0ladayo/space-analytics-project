{{
    config(
        materialized = "table",
        cluster_by = ["location_name", "primary_agency_country"],
    )
}}

with pad_launches as (
    select
        launch_id,
        net,
        launch_year,
        max(launch_year) over () as latest_launch_year,
        last_updated,
        pad_id,
        pad_name,
        location_name,
        latitude,
        longitude,
        pad_total_launches,
        agency_name,
        agency_type,
        agency_country,
        orbit_regime,
        pad_turnaround_hours,
        pad_turnaround_days,
        is_instantaneous_window
    from {{ ref('int_launches__enriched') }}
    where pad_id is not null
),

pad_percentiles as (
    select
        *,
        percentile_cont(pad_turnaround_hours, 0.5) over (
            partition by pad_id
        ) as median_turnaround_hours_raw,
        percentile_cont(
            case
                when launch_year = latest_launch_year and extract(quarter from net) = 1
                    then pad_turnaround_days
            end,
            0.5
        ) over (partition by pad_id) as q1_median_turnaround_days_raw,
        percentile_cont(
            case
                when launch_year = latest_launch_year and extract(quarter from net) > 1
                    then pad_turnaround_days
            end,
            0.5
        ) over (partition by pad_id) as post_q1_median_turnaround_days_raw
    from pad_launches
),

pad_aggregated as (
    select
        pad_id,
        array_agg(pad_name ignore nulls order by last_updated desc, net desc limit 1)[safe_offset(0)] as pad_name,
        array_agg(location_name ignore nulls order by last_updated desc, net desc limit 1)[safe_offset(0)] as location_name,
        array_agg(latitude ignore nulls order by last_updated desc, net desc limit 1)[safe_offset(0)] as latitude,
        array_agg(longitude ignore nulls order by last_updated desc, net desc limit 1)[safe_offset(0)] as longitude,
        approx_top_count(agency_name, 1)[safe_offset(0)].value as primary_agency_name,
        approx_top_count(agency_type, 1)[safe_offset(0)].value as primary_agency_type,
        approx_top_count(agency_country, 1)[safe_offset(0)].value as primary_agency_country,
        approx_top_count(orbit_regime, 1)[safe_offset(0)].value as primary_orbit_regime,
        count(launch_id) as launch_volume,
        max(pad_total_launches) as pad_total_launches_all_time,
        round(any_value(median_turnaround_hours_raw), 2) as median_turnaround_hours,
        round(safe_divide(any_value(median_turnaround_hours_raw), 24.0), 2) as median_turnaround_days,
        round(avg(pad_turnaround_hours), 2) as avg_turnaround_hours,
        round(avg(pad_turnaround_days), 2) as avg_turnaround_days,
        round(min(pad_turnaround_hours), 2) as fastest_turnaround_hours,
        round(any_value(q1_median_turnaround_days_raw), 2) as q1_median_turnaround_days,
        round(any_value(post_q1_median_turnaround_days_raw), 2) as post_q1_median_turnaround_days,
        round(
            100.0 * safe_divide(countif(is_instantaneous_window), count(launch_id)),
            2
        ) as instantaneous_window_share_pct,
        min(net) as first_launch_at,
        max(net) as last_launch_at
    from pad_percentiles
    group by pad_id
)

select
    pad_id,
    pad_name,
    location_name,
    latitude,
    longitude,
    primary_agency_name,
    primary_agency_type,
    primary_agency_country,
    primary_orbit_regime,
    launch_volume,
    pad_total_launches_all_time,
    round(
        100.0 * safe_divide(
            launch_volume,
            nullif(pad_total_launches_all_time, 0)
        ),
        2
    ) as share_of_all_time_pad_launches_pct,
    median_turnaround_hours,
    median_turnaround_days,
    avg_turnaround_hours,
    avg_turnaround_days,
    fastest_turnaround_hours,
    q1_median_turnaround_days,
    post_q1_median_turnaround_days,
    round(
        100.0 * safe_divide(
            post_q1_median_turnaround_days - q1_median_turnaround_days,
            nullif(q1_median_turnaround_days, 0)
        ),
        2
    ) as turnaround_vs_q1_change_pct,
    instantaneous_window_share_pct,
    first_launch_at,
    last_launch_at
from pad_aggregated

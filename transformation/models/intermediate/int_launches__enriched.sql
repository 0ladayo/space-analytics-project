{{
    config(
        materialized = "view",
    )
}}

with staged_launches as (
    select
        launch_id,
        launch_name,
        last_updated,
        net,
        window_start,
        window_end,
        launch_date,
        launch_year,
        launch_quarter,
        status_name,
        status_abbrev,
        fail_reason,
        agency_id,
        agency_name,
        agency_type,
        agency_sector,
        agency_country,
        rocket_id,
        rocket_name,
        mission_name,
        mission_type,
        orbit_name,
        orbit_abbrev,
        orbit_regime,
        pad_id,
        pad_name,
        location_name,
        latitude,
        longitude,
        pad_total_launches
    from {{ ref('stg_space_analytics_raw__launches') }}
),

launch_intervals as (
    select
        *,
        case
            when pad_id is not null
                then lag(net) over (
                    partition by pad_id
                    order by net asc, launch_id asc
                )
        end as prev_pad_launch_net,
        case
            when rocket_name is not null and rocket_name != 'Unknown'
                then lag(net) over (
                    partition by rocket_name
                    order by net asc, launch_id asc
                )
        end as prev_rocket_launch_net,
        case
            when window_start is not null and window_end is not null
                then timestamp_diff(window_end, window_start, second)
        end as raw_window_duration_seconds,
        case
            when window_start is not null and net is not null
                then timestamp_diff(net, window_start, second)
        end as raw_liftoff_slip_seconds
    from staged_launches
),

enriched as (
    select
        launch_id,
        launch_name,
        last_updated,
        net,
        window_start,
        window_end,
        launch_date,
        launch_year,
        launch_quarter,
        status_name,
        status_abbrev,
        fail_reason,
        agency_id,
        agency_name,
        agency_type,
        agency_sector,
        agency_country,
        rocket_id,
        rocket_name,
        mission_name,
        mission_type,
        orbit_name,
        orbit_abbrev,
        orbit_regime,
        pad_id,
        pad_name,
        location_name,
        latitude,
        longitude,
        pad_total_launches,
        prev_pad_launch_net,
        round(
            safe_divide(timestamp_diff(net, prev_pad_launch_net, second), 3600.0),
            2
        ) as pad_turnaround_hours,
        round(
            safe_divide(timestamp_diff(net, prev_pad_launch_net, second), 86400.0),
            2
        ) as pad_turnaround_days,
        prev_rocket_launch_net,
        round(
            safe_divide(timestamp_diff(net, prev_rocket_launch_net, second), 3600.0),
            2
        ) as vehicle_turnaround_hours,
        greatest(raw_window_duration_seconds, 0) as window_duration_seconds,
        round(
            safe_divide(greatest(raw_window_duration_seconds, 0), 60.0),
            2
        ) as window_duration_mins,
        coalesce(raw_window_duration_seconds = 0, false) as is_instantaneous_window,
        case
            when raw_window_duration_seconds is null then 'Unknown'
            when raw_window_duration_seconds <= 0 then 'Instantaneous (0m)'
            when raw_window_duration_seconds <= 1800 then 'Short (1-30m)'
            when raw_window_duration_seconds <= 7200 then 'Medium (31-120m)'
            else 'Extended (>120m)'
        end as window_duration_bucket,
        greatest(raw_liftoff_slip_seconds, 0) as liftoff_slip_seconds,
        round(
            safe_divide(greatest(raw_liftoff_slip_seconds, 0), 60.0),
            2
        ) as liftoff_slip_mins,
        case
            when raw_window_duration_seconds > 0
                then least(
                    round(
                        100.0 * safe_divide(
                            greatest(raw_liftoff_slip_seconds, 0),
                            raw_window_duration_seconds
                        ),
                        2
                    ),
                    100.0
                )
            else 0.0
        end as window_consumed_pct,
        coalesce(raw_liftoff_slip_seconds = 0, false) as is_t0_on_time,
        coalesce(status_abbrev in ('Failure', 'Partial Failure', 'Hold'), false) as is_anomaly,
        coalesce(status_abbrev in ('Failure', 'Partial Failure'), false) as is_launch_failure
    from launch_intervals
)

select * from enriched

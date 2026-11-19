{{
    config(
        materialized = "table",
        partition_by = {
            "field": "net",
            "data_type": "timestamp",
            "granularity": "year",
        },
        cluster_by = ["window_duration_bucket", "is_anomaly", "orbit_regime"],
    )
}}

with launch_reliability_base as (
    select
        launch_id,
        launch_name,
        net,
        launch_date,
        launch_quarter,
        mission_name,
        mission_type,
        rocket_name,
        agency_name,
        agency_type,
        agency_sector,
        agency_country,
        orbit_abbrev,
        orbit_regime,
        pad_id,
        pad_name,
        location_name,
        window_start,
        window_end,
        window_duration_mins,
        window_duration_bucket,
        is_instantaneous_window,
        liftoff_slip_mins,
        window_consumed_pct,
        is_t0_on_time,
        status_name,
        status_abbrev,
        is_anomaly,
        is_launch_failure,
        fail_reason,
        coalesce(
            fail_reason,
            case
                when is_anomaly then coalesce(status_name, status_abbrev, 'Anomaly')
                else 'Nominal'
            end
        ) as anomaly_reason
    from {{ ref('int_launches__enriched') }}
),

bucket_stats as (
    select
        *,
        count(launch_id) over (partition by window_duration_bucket) as bucket_launch_count,
        countif(is_anomaly) over (partition by window_duration_bucket) as bucket_anomaly_count,
        countif(liftoff_slip_mins > 0) over (partition by window_duration_bucket) as bucket_delayed_liftoff_count,
        round(
            avg(liftoff_slip_mins) over (partition by window_duration_bucket),
            2
        ) as bucket_avg_liftoff_slip_mins
    from launch_reliability_base
)

select
    launch_id,
    launch_name,
    net,
    launch_date,
    launch_quarter,
    mission_name,
    mission_type,
    rocket_name,
    agency_name,
    agency_type,
    agency_sector,
    agency_country,
    orbit_abbrev,
    orbit_regime,
    pad_id,
    pad_name,
    location_name,
    window_start,
    window_end,
    window_duration_mins,
    window_duration_bucket,
    is_instantaneous_window,
    liftoff_slip_mins,
    window_consumed_pct,
    is_t0_on_time,
    status_name,
    status_abbrev,
    is_anomaly,
    is_launch_failure,
    fail_reason,
    anomaly_reason,
    bucket_launch_count,
    round(
        100.0 * safe_divide(bucket_anomaly_count, bucket_launch_count),
        2
    ) as bucket_anomaly_rate_pct,
    round(
        100.0 * safe_divide(bucket_delayed_liftoff_count, bucket_launch_count),
        2
    ) as bucket_delayed_liftoff_rate_pct,
    bucket_avg_liftoff_slip_mins
from bucket_stats

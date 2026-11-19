-- Verify launch window duration, liftoff slip, and window consumption percentages remain within valid bounds.
select
    launch_id,
    window_duration_mins,
    liftoff_slip_mins,
    window_consumed_pct
from {{ ref('mart_launch_reliability') }}
where window_duration_mins < 0
   or liftoff_slip_mins < 0
   or window_consumed_pct < 0
   or window_consumed_pct > 100

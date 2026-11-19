-- Verify pad refurbishment turnaround metrics are never negative.
select
    pad_id,
    pad_name,
    median_turnaround_hours,
    avg_turnaround_hours,
    fastest_turnaround_hours
from {{ ref('mart_spaceport_bottlenecks') }}
where median_turnaround_hours < 0
   or avg_turnaround_hours < 0
   or fastest_turnaround_hours < 0

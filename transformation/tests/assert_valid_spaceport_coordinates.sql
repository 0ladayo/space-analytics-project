-- Verify spaceport pad latitude and longitude coordinates fall within valid WGS84 geographic bounds.
select
    pad_id,
    pad_name,
    location_name,
    latitude,
    longitude
from {{ ref('mart_spaceport_bottlenecks') }}
where latitude < -90
   or latitude > 90
   or longitude < -180
   or longitude > 180

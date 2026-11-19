-- Verify orbital market share counts are positive and percentage shares fall within [0, 100].
select
    market_segment_key,
    orbit_regime,
    agency_sector,
    launch_count,
    share_of_orbit_regime_pct,
    share_of_global_orbit_pct,
    vehicle_global_share_pct
from {{ ref('mart_orbital_market_share') }}
where launch_count <= 0
   or share_of_orbit_regime_pct < 0
   or share_of_orbit_regime_pct > 100
   or share_of_global_orbit_pct < 0
   or share_of_global_orbit_pct > 100
   or vehicle_global_share_pct < 0
   or vehicle_global_share_pct > 100

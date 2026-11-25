---
title: Overview
---

# Global Space Launch Operations (2026 – Present)

Orbital launch cadence, spaceport throughput, and market share from January 2026 to date.

{% row %}
  {% dropdown
    id="agency_sector"
    data="space_analytics.fct_launches"
    value_column="agency_sector"
    title="Sector"
    placeholder="All"
    multiple=true
  /%}
  {% dropdown
    id="agency_country"
    data="space_analytics.fct_launches"
    value_column="agency_country"
    title="Country"
    placeholder="All"
    multiple=true
  /%}
  {% dropdown
    id="orbit_regime"
    data="space_analytics.fct_launches"
    value_column="orbit_regime"
    title="Orbit"
    placeholder="All"
    multiple=true
  /%}
{% /row %}

```sql kpi_summary
with filtered as (
  select *
  from space_analytics.fct_launches
  where {{agency_sector.filter}}
    and {{agency_country.filter}}
    and {{orbit_regime.filter}}
),
vehicle_shares as (
  select
    rocket_name,
    count(*) as vehicle_launches
  from filtered
  where rocket_name != 'Unknown'
  group by 1
),
totals as (
  select
    count(*) as total_launches,
    safe_divide(countif(not is_anomaly), count(*)) as launch_success_rate,
    safe_divide(countif(agency_sector = 'Commercial'), count(*)) as commercial_launch_share
  from filtered
)
select
  t.total_launches,
  t.launch_success_rate,
  t.commercial_launch_share,
  safe_divide((select max(vehicle_launches) from vehicle_shares), t.total_launches) as top_vehicle_share
from totals as t
```

{% row %}
  {% big_value
    data="kpi_summary"
    value="any_value(total_launches)"
    title="Total Launches"
    fmt="num0"
    info="Total orbital launches matching the active filters since January 2026."
  /%}
  {% big_value
    data="kpi_summary"
    value="any_value(launch_success_rate)"
    title="Launch Success Rate"
    fmt="pct1"
    info="Percentage of orbital launches completed without a failure, partial failure, or hold."
  /%}
  {% big_value
    data="kpi_summary"
    value="any_value(commercial_launch_share)"
    title="Commercial Launch Share"
    fmt="pct1"
    info="Percentage of orbital launches flown by commercial launch providers."
  /%}
  {% big_value
    data="kpi_summary"
    value="any_value(top_vehicle_share)"
    title="Top Vehicle Share"
    fmt="pct1"
    info="Share of orbital launches flown by the single most active rocket configuration."
  /%}
{% /row %}

## Spaceport Cadence

```sql spaceport_map
select
  pad_name,
  location_name,
  latitude,
  longitude,
  primary_agency_name,
  launch_volume,
  round(avg_turnaround_hours, 1) as avg_turnaround_hours,
  round(median_turnaround_days, 1) as median_turnaround_days
from space_analytics.mart_spaceport_bottlenecks
where latitude is not null
  and longitude is not null
  and pad_id in (
    select distinct pad_id
    from space_analytics.fct_launches
    where {{agency_sector.filter}}
      and {{agency_country.filter}}
      and {{orbit_regime.filter}}
  )
```

{% map
  title="Global Launch Pads"
  subtitle="Drag to rotate globe — bubble size = launches; color = avg turnaround (hours)"
  projection="globe"
  initial_position=[20, -15]
  zoom=1.3
  height=440
%}
  {% point_layer
    data="spaceport_map"
    lat="latitude"
    lng="longitude"
    point_title="pad_name"
    point_subtitle="location_name"
    size_value="launch_volume"
    size_value_fmt="num0"
    color_value="avg_turnaround_hours"
    color_value_fmt="num1"
    color_palette=["#22c55e", "#f59e0b", "#ef4444"]
    max=1500
    tooltip_fields=["primary_agency_name", "median_turnaround_days"]
  /%}
{% /map %}

## Orbital Market Share

```sql top_vehicles
with filtered as (
  select
    rocket_name,
    sum(launch_count) as launches
  from space_analytics.mart_orbital_market_share
  where {{agency_sector.filter}}
    and {{agency_country.filter}}
    and {{orbit_regime.filter}}
    and rocket_name != 'Unknown'
  group by 1
),
total as (
  select sum(launches) as filtered_total from filtered
)
select
  f.rocket_name,
  safe_divide(f.launches, t.filtered_total) as launch_share
from filtered as f
cross join total as t
order by f.launches desc
limit 5
```

{% row %}
  {% bar_chart
    data="space_analytics.mart_orbital_market_share"
    x="orbit_regime"
    y="sum(launch_count) as Launches"
    series="agency_sector"
    stacked="100%"
    filters=["agency_sector", "agency_country", "orbit_regime"]
    x_sort=["LEO", "SSO", "GTO", "TLI", "Other"]
    title="Orbit Regime by Sector"
    height=320
  /%}
  {% horizontal_bar_chart
    data="top_vehicles"
    y="rocket_name"
    x="any_value(launch_share) as `Share of Launches`"
    x_fmt="pct1"
    order="any_value(launch_share) desc"
    title="Top 5 Launch Vehicles"
    height=320
  /%}
{% /row %}

## Launch Cadence & Anomalies

{% bar_chart
  data="space_analytics.fct_launches"
  x="launch_date"
  date_grain="month"
  x_fmt="mmm-yy"
  y="count(*) as Launches"
  y_fmt="num0"
  series="agency_sector"
  filters=["agency_sector", "agency_country", "orbit_regime"]
  title="Monthly Launch Cadence by Sector"
  height=320
  echarts_options={
    yAxis=[{ minInterval=1 }]
  }
/%}

```sql anomaly_log
select
  launch_date,
  launch_name,
  rocket_name,
  status_abbrev,
  anomaly_reason
from space_analytics.mart_launch_reliability
where is_anomaly = true
  and {{agency_sector.filter}}
  and {{agency_country.filter}}
  and {{orbit_regime.filter}}
order by launch_date desc
```

{% table
  data="anomaly_log"
  title="Launch Anomalies"
  order="launch_date desc"
  wrap=true
  subtotals=false
  page_size=10
%}
  {% dimension value="launch_date" title="Date" fmt="shortdate" /%}
  {% dimension value="launch_name" title="Launch" /%}
  {% dimension value="rocket_name" title="Vehicle" /%}
  {% dimension value="status_abbrev" title="Status" /%}
  {% dimension value="anomaly_reason" title="Reason" /%}
{% /table %}

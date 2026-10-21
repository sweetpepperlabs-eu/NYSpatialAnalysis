-- =============================================================================
-- NYC Hydrant Density Analysis. analysis.sql
-- Portfolio Project 2, Modern GIS Accelerator
--
-- Five progressive PostGIS queries that build up to a normalized density
-- analysis and a 100-meter coverage analysis.
--
-- Assumes:
--   - Database "gis" on localhost:5433, user "gis", with PostGIS enabled
--   - Tables loaded:
--       nyc_neighborhoods (polygon, EPSG:4326, geom column called "geom",
--                          attributes including "ntaname" and "boroname")
--       nyc_hydrants      (point,   EPSG:4326, geom column called "geom",
--                          attributes including "hydrant_id")
--   - Spatial indexes on both geom columns (CREATE INDEX ... USING GIST (geom))
--
-- Run all queries:
--   psql -h localhost -p 5433 -U gis -d gis -f analysis.sql
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Filter
--
-- Goal: Sanity check that the data loaded. Pull all neighborhoods in Manhattan.
-- Expected output: ~37 rows (Manhattan neighborhoods).
-- -----------------------------------------------------------------------------

SELECT ntaname, boroname
FROM nyc_neighborhoods
WHERE boroname = 'Manhattan'
ORDER BY ntaname;


-- -----------------------------------------------------------------------------
-- Query 2: Spatial join
--
-- Goal: Match each hydrant to the neighborhood that contains it, using
-- ST_Contains.
-- Expected output: one row per hydrant (~109,725) with the neighborhood name.
-- -----------------------------------------------------------------------------

SELECT h.unitid, n.ntaname, n.boroname
FROM nyc_hydrants AS h
JOIN nyc_neighborhoods AS n
  ON ST_Contains(n.wkb_geometry, h.wkb_geometry)
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Query 3: Aggregate
--
-- Goal: Count hydrants per neighborhood.
-- Expected output: 262 rows (one per neighborhood) with a hydrant_count.
-- -----------------------------------------------------------------------------

SELECT n.ntaname, n.boroname, COUNT(h.*) AS hydrant_count
FROM nyc_neighborhoods AS n
LEFT JOIN nyc_hydrants AS h
  ON ST_Contains(n.wkb_geometry, h.wkb_geometry)
GROUP BY n.ntaname, n.boroname
ORDER BY hydrant_count DESC;


-- -----------------------------------------------------------------------------
-- Query 4: Normalize (this is your headline result)
--
-- Goal: Compute density per square kilometer. Reproject to EPSG:2263
-- (NY State Plane Long Island, feet) before computing area, then convert
-- square feet to square kilometers.
-- Expected output: 262 rows with hydrant_count, area_km2, density_per_km2.
-- -----------------------------------------------------------------------------

SELECT
  n.ntaname,
  n.boroname,
  COUNT(h.*) AS hydrant_count,
  ST_Area(ST_Transform(n.wkb_geometry, 2263)) / 10763910.42 AS area_km2,
  COUNT(h.*) / (ST_Area(ST_Transform(n.wkb_geometry, 2263)) / 10763910.42) AS density_per_km2
FROM nyc_neighborhoods AS n
LEFT JOIN nyc_hydrants AS h
  ON ST_Contains(n.wkb_geometry, h.wkb_geometry)
GROUP BY n.gid
ORDER BY density_per_km2 DESC;


-- -----------------------------------------------------------------------------
-- Query 5: Buffer + Union + Intersection (coverage analysis)
--
-- Goal: For each neighborhood, what percent of its area is within 100 meters
-- of a hydrant? This is the deeper finding.
-- Expected output: 262 rows with neighborhood, area_km2, covered_pct.
-- -----------------------------------------------------------------------------

-- EPSG:2263 uses US survey feet. 100 meters = 100 * 3937/1200 feet.
WITH hydrant_coverage AS (
  SELECT ST_Union(
    ST_Buffer(ST_Transform(wkb_geometry, 2263), 100 * 3937.0 / 1200)
  ) AS coverage_geom
  FROM nyc_hydrants
)
SELECT
  n.ntaname,
  n.boroname,
  ST_Area(ST_Transform(n.wkb_geometry, 2263)) / 10763910.42 AS area_km2,
  ST_Area(
    ST_Intersection(ST_Transform(n.wkb_geometry, 2263), hc.coverage_geom)
  ) / ST_Area(ST_Transform(n.wkb_geometry, 2263)) AS covered_pct
FROM nyc_neighborhoods AS n
CROSS JOIN hydrant_coverage AS hc
ORDER BY covered_pct DESC;


-- =============================================================================
-- Notes for your README
--
-- - Query 1 is your sanity check. Don't skip it.
-- - Query 4 is your headline. Identify the top 5 and bottom 5 neighborhoods.
-- - Query 5 is the deeper insight. Look at the median covered_pct. That number
--   is your case-study finding.
-- =============================================================================


/*
  Stremio Perfect Setup, GA4 BigQuery stats setup
  Views-only version for BigQuery free tier without billing.

  Purpose:
  - Reads GA4 raw export data from:
      `stremio-perfect-setup.analytics_525080461.events_*`
  - Extracts the `wizard_completed` event parameters.
  - Splits comma-separated multi-select values.
  - Produces true_count / false_count style counts.
  - Separates parameter labels into:
      category
      name
  - Adds platform-specific account mode breakdowns:
      Account | Mode (Nuvio)
      Account | Mode (Stremio)
  - Exposes one final GitHub-ready view that can be queried with:
      SELECT *
      FROM `stremio-perfect-setup.public_reports.vw_wizard_completed_github_stats`;

  Important:
  - This file intentionally avoids DML statements such as INSERT, DELETE, UPDATE, and MERGE.
  - This means it can be used without the BigQuery DML billing limitation.
  - Catalog value/name mapping is intentionally left out.
  - GitHub Pages should map catalog keys to display labels on the frontend.
*/


/* ============================================================================
   1. Create the reporting dataset if it does not already exist.

   This dataset will hold only views, not physical summary tables.
   ============================================================================ */

CREATE SCHEMA IF NOT EXISTS
  `stremio-perfect-setup.public_reports`;



/* ============================================================================
   2. Create the daily wizard completion stats view.

   This view:
   - Reads finalized GA4 daily tables only.
   - Excludes intraday tables.
   - Filters to the `wizard_completed` event.
   - Extracts only the known wizard parameters.
   - Maps raw parameter keys to category + name.
   - Splits comma-separated values for multi-select parameters.
   - Converts boolean parameters into one row named `Selected`.
   - Adds a daily total row.
   - Adds platform-specific account mode rows for Nuvio and Stremio.
   - Produces one row per:
       stat_date + category + name + value

   Output columns:
   - stat_date
   - category
   - name
   - value
   - true_count
   - false_count
   ============================================================================ */

CREATE OR REPLACE VIEW
  `stremio-perfect-setup.public_reports.vw_wizard_completed_daily_stats`
AS

WITH completed_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS stat_date,
    event_params,

    LOWER(
      (
        SELECT COALESCE(
          value.string_value,
          CAST(value.int_value AS STRING),
          CAST(value.float_value AS STRING),
          CAST(value.double_value AS STRING)
        )
        FROM UNNEST(event_params)
        WHERE key = 'target'
      )
    ) AS platform_value,

    LOWER(
      (
        SELECT COALESCE(
          value.string_value,
          CAST(value.int_value AS STRING),
          CAST(value.float_value AS STRING),
          CAST(value.double_value AS STRING)
        )
        FROM UNNEST(event_params)
        WHERE key = 'account_mode'
      )
    ) AS account_mode_value,

    (
      SELECT COUNT(1)
      FROM UNNEST(event_params)
      WHERE key = 'services_debrid'
        AND COALESCE(value.string_value, '') != ''
    ) > 0 AS has_debrid_key

  FROM
    `stremio-perfect-setup.analytics_525080461.events_*`
  WHERE
    event_name = 'wizard_completed'
    AND _TABLE_SUFFIX NOT LIKE 'intraday_%'
),

daily_totals AS (
  SELECT
    stat_date,
    COUNT(*) AS total_count
  FROM
    completed_events
  GROUP BY
    stat_date
),

raw_params AS (
  SELECT
    ce.stat_date,
    ep.key AS raw_param_name,

    CASE ep.key
      WHEN 'target' THEN 'Account'
      WHEN 'account_mode' THEN 'Account'
      WHEN 'aio_anime' THEN 'Addons'
      WHEN 'aio_debridio' THEN 'Addons'
      WHEN 'aio_http_addons' THEN 'Addons'
      WHEN 'aio_timeout' THEN 'Addons'
      WHEN 'catalog_categories' THEN 'Catalogs'
      WHEN 'catalog_discover' THEN 'Catalogs'
      WHEN 'aio_formatter_choice' THEN 'Formatter'
      WHEN 'aio_formatter_filename' THEN 'Formatter'
      WHEN 'aio_languages' THEN 'Languages'
      WHEN 'aio_languages_required' THEN 'Languages'
      WHEN 'aio_subtitles' THEN 'Languages'
      WHEN 'services_debrid' THEN 'Services'
      WHEN 'services_keys' THEN 'Services'
      WHEN 'instant_debrid' THEN 'Services'
      WHEN 'aio_language' THEN 'Sorting'
      WHEN 'aio_seeders' THEN 'Sorting'
      ELSE 'Other'
    END AS category,

    CASE ep.key
      WHEN 'target' THEN 'Platform'
      WHEN 'account_mode' THEN 'Mode'
      WHEN 'aio_anime' THEN 'Anime'
      WHEN 'aio_debridio' THEN 'Debridio'
      WHEN 'aio_http_addons' THEN 'HTTP'
      WHEN 'aio_timeout' THEN 'Timeout'
      WHEN 'catalog_categories' THEN 'Categories'
      WHEN 'catalog_discover' THEN 'Discover'
      WHEN 'aio_formatter_choice' THEN 'Style'
      WHEN 'aio_formatter_filename' THEN 'Filename'
      WHEN 'aio_languages' THEN 'Preferred'
      WHEN 'aio_languages_required' THEN 'Required'
      WHEN 'aio_subtitles' THEN 'Subtitles'
      WHEN 'services_debrid' THEN 'Debrid'
      WHEN 'services_keys' THEN 'Keys'
      WHEN 'instant_debrid' THEN 'Instant Debrid'
      WHEN 'aio_language' THEN 'Language'
      WHEN 'aio_seeders' THEN 'Seeders'
      ELSE ep.key
    END AS name,

    COALESCE(
      ep.value.string_value,
      CAST(ep.value.int_value AS STRING),
      CAST(ep.value.float_value AS STRING),
      CAST(ep.value.double_value AS STRING)
    ) AS raw_value

  FROM
    completed_events ce,
    UNNEST(ce.event_params) AS ep

  WHERE
    ep.key IN (
      'target',
      'account_mode',
      'aio_anime',
      'aio_debridio',
      'aio_http_addons',
      'aio_timeout',
      'catalog_categories',
      'catalog_discover',
      'aio_formatter_choice',
      'aio_formatter_filename',
      'aio_languages',
      'aio_languages_required',
      'aio_subtitles',
      'services_debrid',
      'services_keys',
      'instant_debrid',
      'aio_language',
      'aio_seeders'
    )
),

expanded AS (
  SELECT
    stat_date,
    raw_param_name,
    category,
    name,
    TRIM(value) AS value
  FROM
    raw_params,
    UNNEST(
      CASE
        WHEN raw_param_name IN (
          'services_debrid',
          'services_keys',
          'catalog_categories',
          'catalog_discover',
          'aio_languages',
          'aio_subtitles'
        )
        THEN SPLIT(raw_value, ',')
        ELSE [raw_value]
      END
    ) AS value
  WHERE
    raw_value IS NOT NULL
    AND raw_value != ''
),

normalized AS (
  SELECT
    stat_date,
    raw_param_name,
    category,
    name,
    LOWER(value) AS value_lower,
    value
  FROM
    expanded
),

boolean_params AS (
  SELECT
    raw_param_name,
    category,
    name
  FROM
    normalized
  GROUP BY
    raw_param_name,
    category,
    name
  HAVING
    COUNTIF(value_lower NOT IN ('true', 'false')) = 0
),

total_rows AS (
  SELECT
    stat_date,
    'Total' AS category,
    'Completions' AS name,
    'wizard_completed' AS value,
    total_count AS true_count,
    0 AS false_count
  FROM
    daily_totals
),

boolean_summary AS (
  SELECT
    n.stat_date,
    n.category,
    n.name,
    'Selected' AS value,
    COUNTIF(n.value_lower = 'true') AS true_count,
    COUNTIF(n.value_lower = 'false') AS false_count
  FROM
    normalized n
  JOIN
    boolean_params b
  USING
    (raw_param_name, category, name)
  GROUP BY
    n.stat_date,
    n.category,
    n.name
),

non_boolean_summary AS (
  SELECT
    n.stat_date,
    n.category,
    n.name,
    n.value,
    COUNT(*) AS true_count,
    dt.total_count - COUNT(*) AS false_count
  FROM
    normalized n
  JOIN
    daily_totals dt
  USING
    (stat_date)
  LEFT JOIN
    boolean_params b
  USING
    (raw_param_name, category, name)
  WHERE
    b.raw_param_name IS NULL
  GROUP BY
    n.stat_date,
    n.category,
    n.name,
    n.value,
    dt.total_count
),

platform_account_mode_totals AS (
  SELECT
    stat_date,
    platform_value,
    COUNT(*) AS platform_total_count
  FROM
    completed_events
  WHERE
    platform_value IN ('nuvio', 'stremio')
    AND account_mode_value IN ('signin', 'create')
  GROUP BY
    stat_date,
    platform_value
),

platform_account_mode_summary AS (
  SELECT
    ce.stat_date,
    'Account' AS category,
    CASE
      WHEN ce.platform_value = 'nuvio' THEN 'Mode (Nuvio)'
      WHEN ce.platform_value = 'stremio' THEN 'Mode (Stremio)'
    END AS name,
    ce.account_mode_value AS value,
    COUNT(*) AS true_count,
    pt.platform_total_count - COUNT(*) AS false_count
  FROM
    completed_events ce
  JOIN
    platform_account_mode_totals pt
  ON
    ce.stat_date = pt.stat_date
    AND ce.platform_value = pt.platform_value
  WHERE
    ce.platform_value IN ('nuvio', 'stremio')
    AND ce.account_mode_value IN ('signin', 'create')
  GROUP BY
    ce.stat_date,
    ce.platform_value,
    ce.account_mode_value,
    pt.platform_total_count
),

p2p_summary AS (
  SELECT
    stat_date,
    'Addons' AS category,
    'P2P' AS name,
    'p2p' AS value,
    COUNTIF(NOT has_debrid_key) AS true_count,
    COUNTIF(has_debrid_key) AS false_count
  FROM
    completed_events
  GROUP BY
    stat_date
)

SELECT
  stat_date,
  category,
  name,
  value,
  true_count,
  false_count
FROM
  total_rows

UNION ALL

SELECT
  stat_date,
  category,
  name,
  value,
  true_count,
  false_count
FROM
  boolean_summary

UNION ALL

SELECT
  stat_date,
  category,
  name,
  value,
  true_count,
  false_count
FROM
  non_boolean_summary

UNION ALL

SELECT
  stat_date,
  category,
  name,
  value,
  true_count,
  false_count
FROM
  platform_account_mode_summary

UNION ALL

SELECT
  stat_date,
  category,
  name,
  value,
  true_count,
  false_count
FROM
  p2p_summary;



/* ============================================================================
   3. Create the GitHub-ready all-time stats view.

   This is the only view your GitHub Action needs to query.

   It:
   - Aggregates all daily rows from `vw_wizard_completed_daily_stats`.
   - Keeps raw values unchanged.
   - Leaves all value mapping, such as catalog emoji labels, to GitHub Pages.
   - Includes a sort_order column so GitHub Pages can preserve the intended order.
   - Returns the final public table format:
       sort_order
       category
       name
       value
       true_count
       false_count

   GitHub can query this view with:
       SELECT *
       FROM `stremio-perfect-setup.public_reports.vw_wizard_completed_github_stats`;
   ============================================================================ */

CREATE OR REPLACE VIEW
  `stremio-perfect-setup.public_reports.vw_wizard_completed_github_stats`
AS

SELECT
  sort_order,
  category,
  name,
  value,
  true_count,
  false_count
FROM (
  SELECT
    CASE
      WHEN category = 'Total' THEN 0
      WHEN category = 'Account' AND name = 'Platform' THEN 1
      WHEN category = 'Account' AND name = 'Mode' THEN 2
      WHEN category = 'Account' AND name = 'Mode (Nuvio)' THEN 3
      WHEN category = 'Account' AND name = 'Mode (Stremio)' THEN 4
      ELSE 5
    END AS sort_order,
    category,
    name,
    value,
    SUM(true_count) AS true_count,
    SUM(false_count) AS false_count
  FROM
    `stremio-perfect-setup.public_reports.vw_wizard_completed_daily_stats`
  GROUP BY
    category,
    name,
    value
)
ORDER BY
  sort_order,
  category,
  name,
  true_count DESC,
  value;



/* ============================================================================
   4. Query to use from GitHub Actions.

   This is intentionally simple. All aggregation and ordering logic is already
   inside `vw_wizard_completed_github_stats`.

   No BigQuery DML is needed.
   ============================================================================ */

SELECT *
FROM
  `stremio-perfect-setup.public_reports.vw_wizard_completed_github_stats`;

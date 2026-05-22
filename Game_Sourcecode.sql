-- 1. Xử lý dữ số dạng 'E+' ở cột user_id vad event_timestamp

UPDATE dbo.game_events
SET user_id = user_id2
WHERE user_id LIKE '%E+%';

UPDATE dbo.game_events
SET event_timestamp = event_timestamp2
WHERE event_timestamp LIKE '%E+%';

ALTER TABLE dbo.game_events
ALTER COLUMN user_id BIGINT;

ALTER TABLE dbo.game_events
ALTER COLUMN event_timestamp BIGINT;

ALTER TABLE dbo.game_events
DROP COLUMN user_id2, event_timestamp2;



-- 2. Xử lý các dòng duplicate

-- * check qua số dòng khác nhau
SELECT COUNT(*)
FROM (
    SELECT DISTINCT
        user_id,
        event_timestamp,
        batch_event_index,
        event_name,
        app_version,
        session_id,
        time_played,
        country,
        level,
        is_success,
        game_mode,
        device_category,
        mobile_brand_name,
        operating_system
    FROM dbo.game_events
) t;

-- check các dòng duplicate

WITH duplicate_rows AS (
    SELECT 
        *,
        COUNT(*) OVER (
            PARTITION BY
                user_id,
                event_timestamp,
                batch_event_index,
                event_name,
                app_version,
                session_id,
                time_played,
                country,
                level,
                is_success,
                game_mode,
                device_category,
                mobile_brand_name,
                operating_system
        ) AS duplicate_count
    FROM dbo.game_events
)

SELECT *
FROM duplicate_rows
WHERE duplicate_count > 1
ORDER BY duplicate_count DESC, event_timestamp;




-- Xoá các dòng duplicate

WITH duplicate_rows AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                user_id,
                event_timestamp,
                batch_event_index,
                event_name,
                app_version,
                session_id,
                time_played,
                country,
                level,
                is_success,
                game_mode,
                device_category,
                mobile_brand_name,
                operating_system
            ORDER BY (SELECT NULL)
        ) AS rn,

        COUNT(*) OVER (
            PARTITION BY
                user_id,
                event_timestamp,
                batch_event_index,
                event_name,
                app_version,
                session_id,
                time_played,
                country,
                level,
                is_success,
                game_mode,
                device_category,
                mobile_brand_name,
                operating_system
        ) AS duplicate_count

    FROM dbo.game_events
)

DELETE FROM duplicate_rows
WHERE rn > 1;


SELECT COUNT(*) FROM dbo.game_events




-- 3. Xử lý dữ liệu NULL
-- 3a. NULL user_id

-- check 

SELECT 
    t1.session_id,
    t1.user_id AS null_user_id,
    t2.user_id AS matched_user_id
FROM dbo.game_events t1
JOIN dbo.game_events t2
    ON t1.session_id = t2.session_id
WHERE t1.user_id IS NULL
    AND t2.user_id IS NOT NULL;


-- check session_id map tới nhiều user_id khác nhau

SELECT 
    session_id,
    COUNT(DISTINCT user_id) AS distinct_users
FROM dbo.game_events
WHERE user_id IS NOT NULL
GROUP BY session_id
HAVING COUNT(DISTINCT user_id) > 1;



-- fill
/*
========================================
STEP 1:
FILL NULL user_id
WHEN session_id HAS EXACTLY 1 USER
========================================
*/


WITH valid_sessions AS (

    SELECT
        session_id,
        MIN(user_id) AS user_id
    FROM dbo.game_events
    WHERE user_id IS NOT NULL
    GROUP BY session_id
    HAVING COUNT(DISTINCT user_id) = 1

)

UPDATE g
SET g.user_id = v.user_id
FROM dbo.game_events g
JOIN valid_sessions v
    ON g.session_id = v.session_id
WHERE g.user_id IS NULL;


/*
========================================
STEP 2:
FILL AMBIGUOUS CASES
USING NEAREST TIMESTAMP
========================================
*/

WITH nearest_user AS (

    SELECT
        g1.event_timestamp AS null_timestamp,
        g1.session_id,
        g2.user_id,

        ROW_NUMBER() OVER (

            PARTITION BY
                g1.session_id,
                g1.event_timestamp

            ORDER BY
                ABS(g1.event_timestamp - g2.event_timestamp)

        ) AS rn

    FROM dbo.game_events g1

    JOIN dbo.game_events g2
        ON g1.session_id = g2.session_id

    WHERE
        g1.user_id IS NULL
        AND g2.user_id IS NOT NULL

)

UPDATE g
SET g.user_id = n.user_id
FROM dbo.game_events g

JOIN nearest_user n
    ON g.session_id = n.session_id
    AND g.event_timestamp = n.null_timestamp

WHERE
    g.user_id IS NULL
    AND n.rn = 1;



/*
========================================
FILL REMAINING NULL user_id
USING GENERATED NEGATIVE IDS
BASED ON session_id
========================================
*/

WITH null_sessions AS (
    SELECT DISTINCT
        session_id,

        - ROW_NUMBER() OVER (
            ORDER BY session_id
        ) AS generated_user_id

    FROM dbo.game_events
    WHERE user_id IS NULL
)

UPDATE g
SET g.user_id = n.generated_user_id
FROM dbo.game_events g

JOIN null_sessions n
    ON g.session_id = n.session_id

WHERE g.user_id IS NULL;



SELECT COUNT(*) AS remaining_nulls
FROM dbo.game_events
WHERE user_id IS NULL;


/*
========================================
COUNT NULL VALUES FOR EACH COLUMN
========================================
*/

/*
SELECT
    COUNT(*) AS total_rows,

    SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS null_user_id,

    SUM(CASE WHEN event_timestamp IS NULL THEN 1 ELSE 0 END) AS null_event_timestamp,

    SUM(CASE WHEN batch_event_index IS NULL THEN 1 ELSE 0 END) AS null_batch_event_index,

    SUM(CASE WHEN event_name IS NULL THEN 1 ELSE 0 END) AS null_event_name,

    SUM(CASE WHEN app_version IS NULL THEN 1 ELSE 0 END) AS null_app_version,

    SUM(CASE WHEN session_id IS NULL THEN 1 ELSE 0 END) AS null_session_id,

    SUM(CASE WHEN time_played IS NULL THEN 1 ELSE 0 END) AS null_time_played,

    SUM(CASE WHEN country IS NULL THEN 1 ELSE 0 END) AS null_country,

    SUM(CASE WHEN level IS NULL THEN 1 ELSE 0 END) AS null_level,

    SUM(CASE WHEN is_success IS NULL THEN 1 ELSE 0 END) AS null_is_success,

    SUM(CASE WHEN game_mode IS NULL THEN 1 ELSE 0 END) AS null_game_mode,

    SUM(CASE WHEN device_category IS NULL THEN 1 ELSE 0 END) AS null_device_category,

    SUM(CASE WHEN mobile_brand_name IS NULL THEN 1 ELSE 0 END) AS null_mobile_brand_name,

    SUM(CASE WHEN operating_system IS NULL THEN 1 ELSE 0 END) AS null_operating_system

FROM dbo.game_events;

*/

/*
========================================
FILL NULL batch_event_index
USING MAJORITY VALUE
FOR user_id = 24553301114356402
========================================
*/

WITH majority_batch AS (

    SELECT TOP 1
        batch_event_index
    FROM dbo.game_events
    WHERE
        user_id = 24553301114356402
        AND batch_event_index IS NOT NULL
    GROUP BY batch_event_index
    ORDER BY COUNT(*) DESC

)

UPDATE dbo.game_events
SET batch_event_index = (
    SELECT batch_event_index
    FROM majority_batch
)
WHERE
    user_id = 24553301114356402
    AND batch_event_index IS NULL;


/*
========================================
STEP 1:
FILL NULL app_version
USING SAME user_id + session_id
========================================
*/

UPDATE g1
SET g1.app_version = g2.app_version
FROM dbo.game_events g1
JOIN dbo.game_events g2
    ON g1.user_id = g2.user_id
    AND g1.session_id = g2.session_id
WHERE
    g1.app_version IS NULL
    AND g2.app_version IS NOT NULL;



/*
========================================
STEP 2:
FILL REMAINING NULL
USING MAJORITY app_version OF user_id
========================================
*/

WITH user_majority_app AS (

    SELECT
        user_id,
        app_version,

        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY COUNT(*) DESC
        ) AS rn

    FROM dbo.game_events
    WHERE app_version IS NOT NULL
    GROUP BY user_id, app_version

)

UPDATE g
SET g.app_version = u.app_version
FROM dbo.game_events g
JOIN user_majority_app u
    ON g.user_id = u.user_id
WHERE
    g.app_version IS NULL
    AND u.rn = 1;



/*
========================================
STEP 3:
IF USER HAS ONLY 1 ROW
USE GLOBAL MAJORITY app_version
========================================
*/

WITH global_majority AS (

    SELECT TOP 1
        app_version
    FROM dbo.game_events
    WHERE app_version IS NOT NULL
    GROUP BY app_version
    ORDER BY COUNT(*) DESC

)

UPDATE dbo.game_events
SET app_version = (
    SELECT app_version
    FROM global_majority
)
WHERE app_version IS NULL;


*/


/*
========================================
GAME_MODE
========================================
*/


/*
----------------------------------------
STEP 1:
FILL USING SAME user_id + session_id
----------------------------------------
*/


UPDATE g1
SET g1.game_mode = g2.game_mode
FROM dbo.game_events g1
JOIN dbo.game_events g2
    ON g1.user_id = g2.user_id
    AND g1.session_id = g2.session_id
WHERE
    g1.game_mode IS NULL
    AND g2.game_mode IS NOT NULL;


/*
----------------------------------------
STEP 2:
FILL USING USER MAJORITY
----------------------------------------
*/

WITH user_majority_game_mode AS (

    SELECT
        user_id,
        game_mode,

        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY COUNT(*) DESC
        ) AS rn

    FROM dbo.game_events
    WHERE game_mode IS NOT NULL
    GROUP BY user_id, game_mode

)

UPDATE g
SET g.game_mode = u.game_mode
FROM dbo.game_events g
JOIN user_majority_game_mode u
    ON g.user_id = u.user_id
WHERE
    g.game_mode IS NULL
    AND u.rn = 1;


/*
----------------------------------------
STEP 3:
FILL USING GLOBAL MAJORITY
----------------------------------------
*/

WITH global_majority_game_mode AS (

    SELECT TOP 1
        game_mode
    FROM dbo.game_events
    WHERE game_mode IS NOT NULL
    GROUP BY game_mode
    ORDER BY COUNT(*) DESC

)

UPDATE dbo.game_events
SET game_mode = (
    SELECT game_mode
    FROM global_majority_game_mode
)
WHERE game_mode IS NULL;





/*
========================================
MOBILE_BRAND_NAME
========================================
*/



----------------------------------------
STEP 1:
FILL USING SAME user_id + session_id
----------------------------------------
*/

UPDATE g1
SET g1.mobile_brand_name = g2.mobile_brand_name
FROM dbo.game_events g1
JOIN dbo.game_events g2
    ON g1.user_id = g2.user_id
    AND g1.session_id = g2.session_id
WHERE
    g1.mobile_brand_name IS NULL
    AND g2.mobile_brand_name IS NOT NULL;


/*
----------------------------------------
STEP 2:
FILL USING USER MAJORITY
----------------------------------------
*/

WITH user_majority_brand AS (

    SELECT
        user_id,
        mobile_brand_name,

        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY COUNT(*) DESC
        ) AS rn

    FROM dbo.game_events
    WHERE mobile_brand_name IS NOT NULL
    GROUP BY user_id, mobile_brand_name

)

UPDATE g
SET g.mobile_brand_name = u.mobile_brand_name
FROM dbo.game_events g
JOIN user_majority_brand u
    ON g.user_id = u.user_id
WHERE
    g.mobile_brand_name IS NULL
    AND u.rn = 1;


/*
----------------------------------------
STEP 3:
FILL USING GLOBAL MAJORITY
----------------------------------------
*/

WITH global_majority_brand AS (

    SELECT TOP 1
        mobile_brand_name
    FROM dbo.game_events
    WHERE mobile_brand_name IS NOT NULL
    GROUP BY mobile_brand_name
    ORDER BY COUNT(*) DESC

)

UPDATE dbo.game_events
SET mobile_brand_name = (
    SELECT mobile_brand_name
    FROM global_majority_brand
)
WHERE mobile_brand_name IS NULL;






/*
========================================================
STEP 0:
CREATE / RECREATE BACKUP TABLE
========================================================
*/

IF OBJECT_ID('dbo.game_events_null_level_backup', 'U') IS NOT NULL
    DROP TABLE dbo.game_events_null_level_backup;

SELECT *
INTO dbo.game_events_null_level_backup
FROM dbo.game_events
WHERE level IS NULL;


/*
========================================================
STEP 1:
DROP ISOLATED NULL LEVEL ROWS
(USER HAS ONLY 1 EVENT)
========================================================
*/

WITH user_counts AS (

    SELECT
        user_id,
        COUNT(*) AS cnt
    FROM dbo.game_events
    GROUP BY user_id

)

DELETE g
FROM dbo.game_events g
JOIN user_counts u
    ON g.user_id = u.user_id
WHERE
    g.level IS NULL
    AND u.cnt = 1;



/*
========================================================
STEP 2:
CREATE TIMELINE
========================================================
*/

WITH timeline AS (

    SELECT
        *,

        LAG(level) OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp, batch_event_index
        ) AS prev_level,

        LAG(is_success) OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp, batch_event_index
        ) AS prev_success,

        LEAD(level) OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp, batch_event_index
        ) AS next_level

    FROM dbo.game_events

),

inferred AS (

    SELECT
        *,

        CASE

            /*
            ------------------------------------------------
            CASE 1:
            PREV = NEXT
            ------------------------------------------------
            */

            WHEN level IS NULL
                AND prev_level = next_level

            THEN prev_level



            /*
            ------------------------------------------------
            CASE 2:
            PASS → NEXT = PREV + 1
            ------------------------------------------------
            */

            WHEN level IS NULL
                AND prev_success = 'TRUE'
                AND next_level = prev_level + 1

            THEN prev_level + 1



            /*
            ------------------------------------------------
            CASE 3:
            FAIL → SAME LEVEL
            ------------------------------------------------
            */

            WHEN level IS NULL
                AND (
                    prev_success = 'FALSE'
                    OR prev_success IS NULL
                )

            THEN prev_level



            /*
            ------------------------------------------------
            CASE 4:
            BIG GAP
            RANDOM BETWEEN
            ------------------------------------------------
            */

            WHEN level IS NULL
                AND prev_level IS NOT NULL
                AND next_level IS NOT NULL
                AND ABS(next_level - prev_level) > 1

            THEN
                FLOOR(
                    RAND(
                        CHECKSUM(
                            NEWID()
                        )
                    )
                    *
                    (
                        ABS(next_level - prev_level) - 1
                    )
                )
                +
                CASE
                    WHEN next_level > prev_level
                    THEN prev_level + 1
                    ELSE next_level + 1
                END



            ELSE NULL

        END AS inferred_level

    FROM timeline

)



/*
========================================================
STEP 3:
CHECK BEFORE UPDATE
========================================================
*/

SELECT
    user_id,
    event_timestamp,
    prev_level,
    prev_success,
    next_level,
    inferred_level
FROM inferred
WHERE
    level IS NULL
    AND inferred_level IS NOT NULL
ORDER BY
    user_id,
    event_timestamp;



/*
========================================================
STEP 4:
UPDATE
========================================================
*/

WITH timeline AS (

    SELECT
        *,

        LAG(level) OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp, batch_event_index
        ) AS prev_level,

        LAG(is_success) OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp, batch_event_index
        ) AS prev_success,

        LEAD(level) OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp, batch_event_index
        ) AS next_level

    FROM dbo.game_events

),

inferred AS (

    SELECT
        *,

        CASE

            WHEN level IS NULL
                AND prev_level = next_level

            THEN prev_level


            WHEN level IS NULL
                AND prev_success = 'TRUE'
                AND next_level = prev_level + 1

            THEN prev_level + 1


            WHEN level IS NULL
                AND (
                    prev_success = 'FALSE'
                    OR prev_success IS NULL
                )
                AND next_level = prev_level

            THEN prev_level


            WHEN level IS NULL
                AND prev_level IS NOT NULL
                AND next_level IS NOT NULL
                AND ABS(next_level - prev_level) > 1

            THEN
                FLOOR(
                    RAND(
                        CHECKSUM(
                            NEWID()
                        )
                    )
                    *
                    (
                        ABS(next_level - prev_level) - 1
                    )
                )
                +
                CASE
                    WHEN next_level > prev_level
                    THEN prev_level + 1
                    ELSE next_level + 1
                END


            ELSE NULL

        END AS inferred_level

    FROM timeline

)

UPDATE inferred
SET level = inferred_level
WHERE
    level IS NULL
    AND inferred_level IS NOT NULL;

*/




/*
========================================================
FILL NULL time_played
USING MEDIAN OF SAME level + is_success
========================================================
*/


WITH median_table AS (

    SELECT DISTINCT

        level,
        is_success,

        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY time_played
        ) OVER (

            PARTITION BY
                level,
                is_success

        ) AS median_time

    FROM dbo.game_events

    WHERE
        time_played IS NOT NULL
        AND level IS NOT NULL
        AND is_success IS NOT NULL

)

UPDATE g
SET g.time_played = m.median_time

FROM dbo.game_events g

JOIN median_table m
    ON g.level = m.level
    AND g.is_success = m.is_success

WHERE
    g.time_played IS NULL
    AND g.is_success IS NOT NULL;



/*
========================================================
CREATE SUCCESS / FAIL MEDIANS
========================================================
*/



WITH median_stats AS (

    SELECT DISTINCT

        level,
        is_success,

        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY time_played
        ) OVER (

            PARTITION BY
                level,
                is_success

        ) AS median_time

    FROM dbo.game_events

    WHERE
        time_played IS NOT NULL
        AND is_success IS NOT NULL

),

success_median AS (

    SELECT
        level,
        median_time AS success_median
    FROM median_stats
    WHERE is_success = 'TRUE'

),

fail_median AS (

    SELECT
        level,
        median_time AS fail_median
    FROM median_stats
    WHERE is_success = 'FALSE'

)



/*
========================================================
INFER is_success
========================================================
*/

UPDATE g

SET is_success =

    CASE

        WHEN
            ABS(g.time_played - s.success_median)
            <
            ABS(g.time_played - f.fail_median)

        THEN 'TRUE'

        ELSE 'FALSE'

    END

FROM dbo.game_events g

JOIN success_median s
    ON g.level = s.level

JOIN fail_median f
    ON g.level = f.level

WHERE
    g.is_success IS NULL
    AND g.time_played IS NOT NULL;



/*
========================================================
COUNT ROWS:
time_played NULL
BUT is_success NOT NULL
========================================================
*/

SELECT * 
FROM dbo.game_events
WHERE
    time_played IS NULL
    AND is_success IS NOT NULL;





/*
========================================================
COUNT ROWS:
is_success NULL
BUT time_played NOT NULL
========================================================
*/

SELECT *
FROM dbo.game_events
WHERE
    is_success IS NULL
    AND time_played IS NOT NULL;




/*
========================================================
STEP 0:
CHECK INCONSISTENT ROWS
========================================================
*/

SELECT *
FROM dbo.game_events
WHERE

    (
        time_played IS NULL
        AND is_success IS NOT NULL
    )

    OR

    (
        time_played IS NOT NULL
        AND is_success IS NULL
    )

ORDER BY
    user_id,
    event_timestamp,
    batch_event_index;





/*
========================================================
STEP 1:
CREATE MEDIAN TABLE
(level + is_success)
========================================================
*/

WITH median_stats AS (

    SELECT DISTINCT

        level,
        is_success,

        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY time_played
        ) OVER (

            PARTITION BY
                level,
                is_success

        ) AS median_time

    FROM dbo.game_events

    WHERE
        time_played IS NOT NULL
        AND level IS NOT NULL
        AND is_success IS NOT NULL

)



/*
========================================================
STEP 2:
FILL NULL time_played
USING SAME level + is_success MEDIAN
========================================================
*/

UPDATE g

SET g.time_played = m.median_time

FROM dbo.game_events g

JOIN median_stats m
    ON g.level = m.level
    AND g.is_success = m.is_success

WHERE
    g.time_played IS NULL
    AND g.is_success IS NOT NULL;





/*
========================================================
STEP 3:
CREATE SUCCESS / FAIL MEDIANS
========================================================
*/

WITH median_stats AS (

    SELECT DISTINCT

        level,
        is_success,

        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY time_played
        ) OVER (

            PARTITION BY
                level,
                is_success

        ) AS median_time

    FROM dbo.game_events

    WHERE
        time_played IS NOT NULL
        AND is_success IS NOT NULL

),

success_median AS (

    SELECT
        level,
        median_time AS success_median
    FROM median_stats
    WHERE is_success = 'TRUE'

),

fail_median AS (

    SELECT
        level,
        median_time AS fail_median
    FROM median_stats
    WHERE is_success = 'FALSE'

)



/*
========================================================
STEP 4:
INFER is_success
USING NEAREST MEDIAN DISTANCE
========================================================
*/

UPDATE g

SET is_success =

    CASE

        WHEN
            ABS(g.time_played - s.success_median)
            <
            ABS(g.time_played - f.fail_median)

        THEN 'TRUE'

        ELSE 'FALSE'

    END

FROM dbo.game_events g

JOIN success_median s
    ON g.level = s.level

JOIN fail_median f
    ON g.level = f.level

WHERE
    g.is_success IS NULL
    AND g.time_played IS NOT NULL;





/*
========================================================
STEP 5:
CHECK REMAINING INCONSISTENT ROWS
========================================================
*/

SELECT *
FROM dbo.game_events
WHERE

    (
        time_played IS NULL
        AND is_success IS NOT NULL
    )

    OR

    (
        time_played IS NOT NULL
        AND is_success IS NULL
    )

ORDER BY
    user_id,
    event_timestamp,
    batch_event_index;





/*
========================================================
STEP 6:
CHECK FINAL NULL COUNTS
========================================================
*/

SELECT

    SUM(
        CASE
            WHEN time_played IS NULL
            THEN 1
            ELSE 0
        END
    ) AS null_time_played,

    SUM(
        CASE
            WHEN is_success IS NULL
            THEN 1
            ELSE 0
        END
    ) AS null_is_success

FROM dbo.game_events;



/*
========================================================
DROP REMAINING INCONSISTENT ROWS
========================================================
*/

DELETE
FROM dbo.game_events
WHERE

    (
        time_played IS NULL
        AND is_success IS NOT NULL
    )

    OR

    (
        time_played IS NOT NULL
        AND is_success IS NULL
    );



-- I. EXPLORATORY DATA ANALYSIS (EDA)

-- 1. DATASET OVERVIEW
/*
Tổng số:
rows
users
sessions
levels
countries
app versions
*/



SELECT

    COUNT(*) AS total_events,

    COUNT(DISTINCT user_id) AS total_users,

    COUNT(DISTINCT session_id) AS total_sessions,

    COUNT(DISTINCT level) AS total_levels,

    COUNT(DISTINCT country) AS total_countries,

    COUNT(DISTINCT app_version) AS total_app_versions

FROM dbo.game_events;

*/


-- 2. DATA SCHEMA UNDERSTANDING

-- 3. DATA QUALITY & ANOMALY CHECKS

-- 4. DESCRIPTIVE STATISTICS


4.1 Event distribution

/*
========================================================
EVENT DISTRIBUTION
========================================================
*/

SELECT
    event_name,
    COUNT(*) AS total_events
FROM dbo.game_events
GROUP BY event_name
ORDER BY total_events DESC;


4.2 Success rate

/*
========================================================
SUCCESS RATE
========================================================
*/

SELECT

    SUM(
        CASE
            WHEN is_success = 'TRUE'
            THEN 1
            ELSE 0
        END
    ) * 1.0

    /

    COUNT(is_success)

    AS success_rate

FROM dbo.game_events
WHERE is_success IS NOT NULL;


4.3 Playtime statistics

/*
========================================================
PLAYTIME STATS
========================================================
*/

SELECT

    MIN(time_played) AS min_time,

    MAX(time_played) AS max_time,

    AVG(time_played * 1.0) AS avg_time

FROM dbo.game_events
WHERE time_played IS NOT NULL;


4.4 Top countries

/*
========================================================
TOP COUNTRIES
========================================================
*/

SELECT TOP 10

    country,
    COUNT(DISTINCT user_id) AS total_users

FROM dbo.game_events

GROUP BY country

ORDER BY total_users DESC;


4.5 Device distribution

/*
========================================================
DEVICE DISTRIBUTION
========================================================
*/

SELECT

    device_category,
    COUNT(*) AS total_events

FROM dbo.game_events

GROUP BY device_category

ORDER BY total_events DESC;


4.6 Level distribution

/*
========================================================
LEVEL DISTRIBUTION
========================================================
*/

SELECT

    level,
    COUNT(*) AS total_attempts

FROM dbo.game_events

GROUP BY level

ORDER BY level;


4.7 Average Retries Per Level

/*
========================================================
AVERAGE RETRIES PER LEVEL
========================================================
*/

WITH user_level_attempts AS (

    SELECT

        user_id,
        level,

        COUNT(*) AS total_attempts

    FROM dbo.game_events

    WHERE event_name = 'level_start'

    GROUP BY
        user_id,
        level

)

SELECT

    level,

    AVG(total_attempts * 1.0) AS avg_attempts_per_user,

    MAX(total_attempts) AS max_attempts,

    MIN(total_attempts) AS min_attempts

FROM user_level_attempts

GROUP BY level

ORDER BY level;

4.8 Difficulty Spike Preview

A. Highest Fail Rate Levels

/*
========================================================
FAIL RATE BY LEVEL
========================================================
*/

SELECT

    level,

    SUM(
        CASE
            WHEN is_success = 'FALSE'
            THEN 1
            ELSE 0
        END
    ) * 1.0

    /

    COUNT(is_success)

    AS fail_rate,

    COUNT(*) AS total_attempts

FROM dbo.game_events

WHERE is_success IS NOT NULL

GROUP BY level

HAVING COUNT(*) >= 30

ORDER BY fail_rate DESC;


B. Highest Playtime Levels

/*
========================================================
HIGHEST PLAYTIME LEVELS
========================================================
*/

SELECT

    level,

    AVG(time_played * 1.0) AS avg_playtime,

    MAX(time_played) AS max_playtime,

    COUNT(*) AS total_attempts

FROM dbo.game_events

WHERE time_played IS NOT NULL

GROUP BY level

HAVING COUNT(*) >= 30

ORDER BY avg_playtime DESC;


C. Combined Difficulty View 

Join fail rate + playtime

/*
========================================================
COMBINED DIFFICULTY METRICS
========================================================
*/

WITH fail_stats AS (

    SELECT

        level,

        SUM(
            CASE
                WHEN is_success = 'FALSE'
                THEN 1
                ELSE 0
            END
        ) * 1.0

        /

        COUNT(is_success)

        AS fail_rate

    FROM dbo.game_events

    WHERE is_success IS NOT NULL

    GROUP BY level

),

playtime_stats AS (

    SELECT

        level,

        AVG(time_played * 1.0) AS avg_playtime

    FROM dbo.game_events

    WHERE time_played IS NOT NULL

    GROUP BY level

)

SELECT

    f.level,

    f.fail_rate,

    p.avg_playtime

FROM fail_stats f

JOIN playtime_stats p
    ON f.level = p.level

ORDER BY
    f.fail_rate DESC,
    p.avg_playtime DESC;




II.Phân tích tỉ lệ bỏ chơi (Drop-off) theo cấp độ (Level)

1. DEFINITION 1 — NEXT LEVEL DROP-OFF
/*
========================================================
DROP-OFF RATE
BASED ON NEXT LEVEL PROGRESSION
========================================================
*/



WITH user_progression AS (

    SELECT

        user_id,
        MAX(level) AS max_level

    FROM dbo.game_events

    GROUP BY user_id

),

level_reach AS (

    SELECT

        level,

        COUNT(DISTINCT user_id) AS users_reached

    FROM dbo.game_events

    GROUP BY level

),

dropoff AS (

    SELECT

        max_level AS level,

        COUNT(*) AS dropped_users

    FROM user_progression

    GROUP BY max_level

)

SELECT

    r.level,

    r.users_reached,

    ISNULL(d.dropped_users, 0) AS dropped_users,

    ISNULL(d.dropped_users, 0) * 1.0
    /
    r.users_reached

    AS dropoff_rate

FROM level_reach r

LEFT JOIN dropoff d
    ON r.level = d.level

ORDER BY r.level;


2. DEFINITION 2 — SESSION-ENDING DROP-OFF

event cuối cùng của user
/*
========================================================
SESSION-END DROP-OFF
========================================================
*/
WITH last_events AS (
    SELECT
        user_id,
        MAX(event_timestamp) AS last_time

    FROM dbo.game_events
    GROUP BY user_id
),

user_last_level AS (
    SELECT
        g.user_id,
        g.level
    FROM dbo.game_events g

    JOIN last_events l
        ON g.user_id = l.user_id
        AND g.event_timestamp = l.last_time
)
SELECT
    level,

    COUNT(*) AS users_dropped
FROM user_last_level
GROUP BY level
ORDER BY users_dropped DESC;



DEFINITION 3 — FAIL-BASED DROP-OFF

avg fail attempts before churn
/*
========================================================
FAIL BEFORE DROP-OFF
========================================================
*/
WITH user_max_level AS (
    SELECT
        user_id,
        MAX(level) AS max_level

    FROM dbo.game_events

    GROUP BY user_id
)

SELECT
    g.level,
    COUNT(*) AS fail_events
FROM dbo.game_events g

JOIN user_max_level u
    ON g.user_id = u.user_id
    AND g.level = u.max_level

WHERE
    g.is_success = 'FALSE'

GROUP BY g.level

ORDER BY fail_events DESC;



III. Phân tích Độ khó của Level

1. METRIC 1 — FAIL RATE 
 
fail_rate = failed_attempts / total_attempts

/*
========================================================
FAIL RATE BY LEVEL
========================================================
*/
SELECT
    level,

    SUM(
        CASE
            WHEN is_success = 'FALSE'
            THEN 1
            ELSE 0
        END
    ) * 1.0
    /
    COUNT(is_success)

    AS fail_rate,

    COUNT(*) AS total_attempts

FROM dbo.game_events
WHERE is_success IS NOT NULL
GROUP BY level
HAVING COUNT(*) >= 30
ORDER BY fail_rate DESC;


2. METRIC 2 — AVERAGE RETRIES

số lần trung bình user thử lại level

/*
========================================================
AVERAGE ATTEMPTS PER USER
========================================================
*/
WITH user_level_attempts AS (
    SELECT
        user_id,
        level,
        COUNT(*) AS attempts
    FROM dbo.game_events
    WHERE event_name = 'level_start'
    GROUP BY
        user_id,
        level
)
SELECT
    level,
    AVG(attempts * 1.0) AS avg_attempts,
    MAX(attempts) AS max_attempts
FROM user_level_attempts

GROUP BY level

ORDER BY avg_attempts DESC;


3. METRIC 3 — AVERAGE PLAYTIME

thời gian trung bình để hoàn thành

/*
========================================================
AVERAGE PLAYTIME BY LEVEL
========================================================
*/

SELECT

    level,

    AVG(time_played * 1.0) AS avg_playtime,

    MAX(time_played) AS max_playtime,

    COUNT(*) AS total_attempts

FROM dbo.game_events

WHERE time_played IS NOT NULL

GROUP BY level

HAVING COUNT(*) >= 30

ORDER BY avg_playtime DESC;



4. METRIC 4 — DROP-OFF RATE
(reuse từ câu 2)


--> COMBINED DIFFICULTY SCORE

difficulty_score
=
0.4 * fail_rate
+
0.3 * normalized_retries
+
0.2 * normalized_playtime
+
0.1 * dropoff_rate


/*
========================================================
COMBINED DIFFICULTY METRICS
========================================================
*/

WITH fail_stats AS (

    SELECT

        level,

        SUM(
            CASE
                WHEN is_success = 'FALSE'
                THEN 1
                ELSE 0
            END
        ) * 1.0

        /

        COUNT(is_success)

        AS fail_rate

    FROM dbo.game_events

    WHERE is_success IS NOT NULL

    GROUP BY level

),

playtime_stats AS (

    SELECT

        level,

        AVG(time_played * 1.0) AS avg_playtime

    FROM dbo.game_events

    WHERE time_played IS NOT NULL

    GROUP BY level

),

retry_stats AS (

    SELECT

        level,

        AVG(attempts * 1.0) AS avg_attempts

    FROM (

        SELECT

            user_id,
            level,
            COUNT(*) AS attempts

        FROM dbo.game_events

        WHERE event_name = 'level_start'

        GROUP BY
            user_id,
            level

    ) t

    GROUP BY level

)

SELECT

    f.level,

    f.fail_rate,

    p.avg_playtime,

    r.avg_attempts

FROM fail_stats f

JOIN playtime_stats p
    ON f.level = p.level

JOIN retry_stats r
    ON f.level = r.level

ORDER BY
    f.fail_rate DESC,
    r.avg_attempts DESC,
    p.avg_playtime DESC;




*** TẠO CÁC TABLE ĐẨY QUA POWER BI

/*
========================================================
========================================================
CREATE CLEAN ANALYTICS TABLES
FOR POWER BI
========================================================
========================================================
*/



/*
========================================================
1. CLEAN MASTER TABLE
========================================================
*/

IF OBJECT_ID('dbo.game_events_clean', 'U') IS NOT NULL
    DROP TABLE dbo.game_events_clean;

SELECT *
INTO dbo.game_events_clean
FROM dbo.game_events;





/*
========================================================
2. LEVEL DROPOFF TABLE
========================================================
*/

IF OBJECT_ID('dbo.level_dropoff', 'U') IS NOT NULL
    DROP TABLE dbo.level_dropoff;


WITH user_progression AS (

    SELECT

        user_id,
        MAX(level) AS max_level

    FROM dbo.game_events_clean

    GROUP BY user_id

),

level_reach AS (

    SELECT

        level,

        COUNT(DISTINCT user_id) AS users_reached

    FROM dbo.game_events_clean

    GROUP BY level

),

dropoff AS (

    SELECT

        max_level AS level,

        COUNT(*) AS dropped_users

    FROM user_progression

    GROUP BY max_level

)

SELECT

    r.level,

    r.users_reached,

    ISNULL(d.dropped_users, 0) AS dropped_users,

    ISNULL(d.dropped_users, 0) * 1.0
    /
    r.users_reached

    AS dropoff_rate

INTO dbo.level_dropoff

FROM level_reach r

LEFT JOIN dropoff d
    ON r.level = d.level;





/*
========================================================
3. LEVEL DIFFICULTY TABLE
========================================================
*/

IF OBJECT_ID('dbo.level_difficulty', 'U') IS NOT NULL
    DROP TABLE dbo.level_difficulty;


WITH fail_stats AS (

    SELECT

        level,

        SUM(
            CASE
                WHEN is_success = 'FALSE'
                THEN 1
                ELSE 0
            END
        ) * 1.0

        /

        COUNT(is_success)

        AS fail_rate

    FROM dbo.game_events_clean

    WHERE is_success IS NOT NULL

    GROUP BY level

),

playtime_stats AS (

    SELECT

        level,

        AVG(time_played * 1.0) AS avg_playtime,

        MAX(time_played) AS max_playtime

    FROM dbo.game_events_clean

    WHERE time_played IS NOT NULL

    GROUP BY level

),

retry_stats AS (

    SELECT

        level,

        AVG(attempts * 1.0) AS avg_attempts

    FROM (

        SELECT

            user_id,
            level,

            COUNT(*) AS attempts

        FROM dbo.game_events_clean

        WHERE event_name = 'level_start'

        GROUP BY
            user_id,
            level

    ) t

    GROUP BY level

)

SELECT

    f.level,

    f.fail_rate,

    p.avg_playtime,

    p.max_playtime,

    r.avg_attempts

INTO dbo.level_difficulty

FROM fail_stats f

JOIN playtime_stats p
    ON f.level = p.level

JOIN retry_stats r
    ON f.level = r.level;





/*
========================================================
4. USER PROGRESSION TABLE
========================================================
*/

IF OBJECT_ID('dbo.user_progression', 'U') IS NOT NULL
    DROP TABLE dbo.user_progression;


SELECT

    user_id,

    MAX(level) AS max_level,

    COUNT(*) AS total_events,

    COUNT(DISTINCT session_id) AS total_sessions,

    SUM(
        CASE
            WHEN is_success = 'FALSE'
            THEN 1
            ELSE 0
        END
    ) AS total_failures,

    SUM(
        CASE
            WHEN is_success = 'TRUE'
            THEN 1
            ELSE 0
        END
    ) AS total_successes

INTO dbo.user_progression

FROM dbo.game_events_clean

GROUP BY user_id;





/*
========================================================
5. LEVEL SUMMARY TABLE
========================================================
*/

IF OBJECT_ID('dbo.level_summary', 'U') IS NOT NULL
    DROP TABLE dbo.level_summary;


SELECT

    g.level,

    COUNT(*) AS total_attempts,

    COUNT(DISTINCT g.user_id) AS unique_users,

    AVG(g.time_played * 1.0) AS avg_playtime,

    SUM(
        CASE
            WHEN g.is_success = 'TRUE'
            THEN 1
            ELSE 0
        END
    ) * 1.0

    /

    NULLIF(COUNT(g.is_success), 0)

    AS success_rate,

    d.dropoff_rate,

    ld.fail_rate,

    ld.avg_attempts

INTO dbo.level_summary

FROM dbo.game_events_clean g

LEFT JOIN dbo.level_dropoff d
    ON g.level = d.level

LEFT JOIN dbo.level_difficulty ld
    ON g.level = ld.level

GROUP BY

    g.level,
    d.dropoff_rate,
    ld.fail_rate,
    ld.avg_attempts;





/*
========================================================
6. CHECK CREATED TABLES
========================================================
*/

SELECT *
FROM dbo.level_dropoff;


SELECT TOP 10 *
FROM dbo.level_difficulty;


SELECT TOP 10 *
FROM dbo.user_progression;


SELECT *
FROM dbo.level_summary;

SELECT TOP 10 *
FROM dbo.game_events_clean;
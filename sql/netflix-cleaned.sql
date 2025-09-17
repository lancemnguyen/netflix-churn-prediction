-- Schema Setup
CREATE TABLE
    netflix_cleaned LIKE netflix_customer_churn;

INSERT netflix_cleaned
SELECT
    *
FROM
    netflix_customer_churn;

CREATE INDEX idx_customer_id ON netflix_cleaned (customer_id (36));

-- Drop/Rename columns
ALTER TABLE netflix_cleaned
RENAME COLUMN device TO primary_device;

ALTER TABLE netflix_cleaned
RENAME COLUMN number_of_profiles TO profile_count;

ALTER TABLE netflix_cleaned
-- drop monthly_fee since we already have subscription_type, avoids multicollinearity
-- subscription_type has better categorical interpretability for a model
DROP COLUMN monthly_fee;

-- avg_watch_time_per_day will be recalculated during analysis using watch_hours / tenure_days
ALTER TABLE netflix_cleaned
DROP COLUMN avg_watch_time_per_day;

-- Add new columns
ALTER TABLE netflix_cleaned
ADD COLUMN tenure_days INT UNSIGNED;

ALTER TABLE netflix_cleaned
ADD COLUMN multi_device BOOLEAN;

ALTER TABLE netflix_cleaned
ADD COLUMN activity_level VARCHAR(255);

ALTER TABLE netflix_cleaned
ADD COLUMN genres_watched INT UNSIGNED;

ALTER TABLE netflix_cleaned
ADD COLUMN support_tickets INT UNSIGNED;

-- Independent Variables
-- These can be generated in any order since they don't depend on each other

-- tenure_days (Foundation)
UPDATE netflix_cleaned AS n
JOIN (
    SELECT
        customer_id,
        FLOOR(
            CASE
                WHEN RAND () < 0.3 THEN POW (RAND (), 0.5) * 365 -- More long-term users
                WHEN RAND () < 0.7 THEN POW (RAND (), 1.5) * 730 -- Most users in the mid-range
                ELSE POW (RAND (), 2) * 1095 -- A smaller group of very new users
            END
        ) + 1 AS new_tenure_days
    FROM
        netflix_cleaned
) r ON n.customer_id = r.customer_id
SET
    n.tenure_days = r.new_tenure_days;

-- gender
UPDATE netflix_cleaned
SET
    gender = CASE
        WHEN RAND () < 0.5 THEN 'Male'
        ELSE 'Female'
    END;

-- subscription_type
UPDATE netflix_cleaned AS n
SET
    n.subscription_type = (
        SELECT
            CASE
                WHEN rn < 0.25 THEN 'Standard with ads'
                WHEN rn < 0.55 THEN 'Premium'
                ELSE 'Standard'
            END AS new_subscription_type
        FROM
            (
                SELECT
                    customer_id,
                    RAND () AS rn
                FROM
                    netflix_cleaned
                WHERE
                    customer_id = n.customer_id
            ) AS random_numbers
    );

-- region
UPDATE netflix_cleaned AS n
SET
    n.region = (
        SELECT
            CASE
                WHEN rn < 0.03 THEN 'Oceania'
                WHEN rn < 0.10 THEN 'Africa'
                WHEN rn < 0.25 THEN 'South America'
                WHEN rn < 0.45 THEN 'Asia'
                WHEN rn < 0.70 THEN 'Europe'
                ELSE 'North America'
            END AS new_region
        FROM
            (
                SELECT
                    customer_id,
                    RAND () AS rn
                FROM
                    netflix_cleaned
                WHERE
                    customer_id = n.customer_id
            ) AS random_numbers
    );

-- primary device
UPDATE netflix_cleaned AS n
SET
    n.primary_device = (
        SELECT
            CASE
                WHEN rn < 0.10 THEN 'Laptop'
                WHEN rn < 0.20 THEN 'Desktop'
                WHEN rn < 0.40 THEN 'Tablet'
                WHEN rn < 0.60 THEN 'Mobile'
                ELSE 'TV'
            END AS new_primary_device
        FROM
            (
                SELECT
                    customer_id,
                    RAND () AS rn
                FROM
                    netflix_cleaned
                WHERE
                    customer_id = n.customer_id
            ) AS random_numbers
    );

-- payment_method
UPDATE netflix_cleaned AS n
SET
    n.payment_method = (
        SELECT
            CASE
                WHEN rn < 0.10 THEN 'Third-party Bundle'
                WHEN rn < 0.20 THEN 'Digital Wallet'
                WHEN rn < 0.40 THEN 'Debit Card'
                ELSE 'Credit Card'
            END AS new_payment_method
        FROM
            (
                SELECT
                    customer_id,
                    RAND () AS rn
                FROM
                    netflix_cleaned
                WHERE
                    customer_id = n.customer_id
            ) AS random_numbers
    );

-- multi_device
UPDATE netflix_cleaned
SET
    multi_device = IF (RAND () < 0.5, 1, 0);

-- Dependent Variables

-- last_login_days (Dependent on tenure_days)
UPDATE netflix_cleaned AS n
JOIN (
    SELECT
        customer_id,
        FLOOR(
            CASE
                WHEN tenure_days >= 365 THEN RAND () * 90 -- Long-term users are more likely to be active
                WHEN tenure_days >= 90 THEN RAND () * 180 -- Mid-term users have a wider range
                ELSE RAND () * tenure_days -- New users can have any login date up to their tenure
            END
        ) AS new_last_login
    FROM
        netflix_cleaned
) r ON n.customer_id = r.customer_id
SET
    n.last_login_days = LEAST (r.new_last_login, n.tenure_days);

-- watch_hours (Dependent on tenure_days and last_login_days)
-- This query models a daily watch rate that drops over time.
UPDATE netflix_cleaned AS n
JOIN (
    SELECT
        customer_id,
        FLOOR(
            (0.5 + RAND () * 2) * GREATEST (tenure_days - last_login_days, 0) * (0.7 + RAND () * 0.6)
        ) AS new_watch_hours
    FROM
        netflix_cleaned
) r ON n.customer_id = r.customer_id
SET
    n.watch_hours = r.new_watch_hours;

-- create activity_level (categorical variable) to compare prediction model with last_login_days (continuous variable)
-- It's often more intuitive for a model to use discrete categories than a continuous number, as it groups customers into meaningful behavioral segments.
-- activity_level (Dependent on last_login_days)
UPDATE netflix_cleaned
SET
    activity_level = CASE
        WHEN last_login_days <= 30 THEN 'Active'
        WHEN last_login_days > 30
        AND last_login_days <= 90 THEN 'Idle'
        ELSE 'At-risk'
    END;

-- genres_watched (Dependent on watch_hours)
UPDATE netflix_cleaned AS n
JOIN (
    SELECT
        customer_id,
        CASE
            WHEN watch_hours > 500 THEN FLOOR(3 + RAND () * 6) -- 3-8 genres
            WHEN watch_hours > 200 THEN FLOOR(2 + RAND () * 3) -- 2-4 genres
            WHEN watch_hours > 10 THEN FLOOR(1 + RAND () * 2) -- 1-2 genres
            ELSE 1
        END AS new_genres_watched
    FROM
        netflix_cleaned
) r ON n.customer_id = r.customer_id
SET
    n.genres_watched = r.new_genres_watched;

-- support_tickets (Dependent on last_login_days)
UPDATE netflix_cleaned AS n
JOIN (
    SELECT
        customer_id,
        CASE
            WHEN last_login_days > 60 THEN FLOOR(RAND () * 4) -- 0-3 tickets
            WHEN last_login_days > 30 THEN FLOOR(RAND () * 3) -- 0-2 tickets
            ELSE FLOOR(RAND () * 2) -- 0-1 tickets
        END AS new_support_tickets
    FROM
        netflix_cleaned
) r ON n.customer_id = r.customer_id
SET
    n.support_tickets = r.new_support_tickets;

-- churned (Dependent on last_login_days, watch_hours, support_tickets)
UPDATE netflix_cleaned AS n
JOIN (
    SELECT
        customer_id,
        CASE
            WHEN last_login_days > 90
            AND watch_hours < 20
            AND support_tickets >= 3 THEN IF (RAND () < 0.80, 1, 0) -- High risk
            WHEN last_login_days > 60
            AND watch_hours < 50
            AND support_tickets = 2 THEN IF (RAND () < 0.60, 1, 0) -- Medium risk
            WHEN last_login_days > 30
            AND watch_hours < 100
            AND support_tickets = 1 THEN IF (RAND () < 0.40, 1, 0) -- Low risk
            ELSE IF (RAND () < 0.05, 1, 0) -- Very active users rarely churn
        END AS new_churned
    FROM
        netflix_cleaned
) r ON n.customer_id = r.customer_id
SET
    n.churned = r.new_churned;

-- check illogical violations
SELECT
    *
FROM
    netflix_cleaned
WHERE
    last_login_days > tenure_days
    OR watch_hours < 0
    OR watch_hours > (tenure_days - last_login_days) * 24
    OR watch_hours > 3190
    OR tenure_days > 1095
    -- Activity level mismatch
    OR (
        activity_level = 'Active'
        AND last_login_days > 30
    )
    OR (
        activity_level = 'Idle'
        AND (
            last_login_days <= 30
            OR last_login_days > 90
        )
    )
    OR (
        activity_level = 'At-risk'
        AND last_login_days <= 90
    )
    -- Genres watched vs watch hours
    OR (
        watch_hours < 10
        AND genres_watched > 1
    )
    OR (
        watch_hours > 200
        AND genres_watched = 1
    )
    -- Support tickets vs activity
    OR (
        last_login_days <= 30
        AND support_tickets >= 2
    )
    -- Churn logic violations
    OR (
        activity_level = 'Active'
        AND churned = 1
    )
    OR (
        activity_level = 'At-risk'
        AND watch_hours < 20
        AND support_tickets >= 2
        AND churned = 0
    )
    OR (
        tenure_days < 30
        AND churned = 1
    )
    -- Churned but highly active
    OR (
        churned = 1
        AND last_login_days <= 15
        AND watch_hours >= 50
    )
    -- Multi-device
    OR multi_device NOT IN (0, 1)
    -- Categorical variables
    OR gender NOT IN ('Male', 'Female', 'Other')
    OR subscription_type NOT IN ('Standard', 'Premium', 'Standard with ads')
    OR region NOT IN (
        'North America',
        'Europe',
        'Asia',
        'South America',
        'Africa',
        'Oceania'
    )
    OR primary_device NOT IN ('Laptop', 'Desktop', 'Tablet', 'Mobile', 'TV')
    OR payment_method NOT IN (
        'Credit Card',
        'Debit Card',
        'Digital Wallet',
        'Third-party Bundle'
    )
    -- No watch hours after signing up
    OR (
        watch_hours = 0
        AND tenure_days > 7
    );

SELECT
    *
FROM
    netflix_cleaned;

SELECT
    support_tickets,
    COUNT(*) AS count
FROM
    netflix_cleaned
GROUP BY
    support_tickets
ORDER BY
    count DESC;

-- fields for future work
-- product feature usage
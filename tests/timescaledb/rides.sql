--
-- https://docs.timescale.com/tutorials/latest/nyc-taxi-cab/dataset-nyc/
--

BEGIN;

CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE "rides"(
    vendor_id TEXT,
    pickup_datetime TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    dropoff_datetime TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    passenger_count NUMERIC,
    trip_distance NUMERIC,
    pickup_longitude  NUMERIC,
    pickup_latitude   NUMERIC,
    rate_code         INTEGER,
    dropoff_longitude NUMERIC,
    dropoff_latitude  NUMERIC,
    payment_type INTEGER,
    fare_amount NUMERIC,
    extra NUMERIC,
    mta_tax NUMERIC,
    tip_amount NUMERIC,
    tolls_amount NUMERIC,
    improvement_surcharge NUMERIC,
    total_amount NUMERIC
);
SELECT create_hypertable('rides', 'pickup_datetime', 'payment_type', 2, create_default_indexes=>FALSE);
CREATE INDEX ON rides (vendor_id, pickup_datetime desc);
CREATE INDEX ON rides (pickup_datetime desc, vendor_id);
CREATE INDEX ON rides (rate_code, pickup_datetime DESC);
CREATE INDEX ON rides (passenger_count, pickup_datetime desc);

CREATE TABLE IF NOT EXISTS "payment_types"(
    payment_type INTEGER,
    description TEXT
);
INSERT INTO payment_types(payment_type, description) VALUES
(1, 'credit card'),
(2, 'cash'),
(3, 'no charge'),
(4, 'dispute'),
(5, 'unknown'),
(6, 'voided trip');

CREATE TABLE IF NOT EXISTS "rates"(
    rate_code   INTEGER,
    description TEXT
);
INSERT INTO rates(rate_code, description) VALUES
(1, 'standard rate'),
(2, 'JFK'),
(3, 'Newark'),
(4, 'Nassau or Westchester'),
(5, 'negotiated fare'),
(6, 'group ride');

-- Basic Hypertable with Time-Based Partitioning

CREATE TABLE sensor_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id INTEGER NOT NULL,
    value DOUBLE PRECISION
);

SELECT create_hypertable('sensor_data', 'time');

-- Without -time



-- Hypertable with Space Partitioning

CREATE TABLE multi_sensor_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id INTEGER NOT NULL,
    value DOUBLE PRECISION,
    location TEXT
);

SELECT create_hypertable('multi_sensor_data', 'time', 'sensor_id', number_partitions => 4 );

-- Hypertable with Compression

CREATE TABLE compressed_data (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION
);


INSERT INTO compressed_data (time, device_id, temperature, humidity) VALUES
('2024-01-01 00:00:00', 1, 23.5, 45.2),
('2024-01-01 01:00:00', 2, 22.1, 46.3),
('2024-01-02 02:00:00', 1, 24.3, 44.1),
('2024-01-02 03:00:00', 2, 23.8, 47.6);

COMMIT;

SELECT create_hypertable('compressed_data', 'time', migrate_data => true);

-- Enable compression
ALTER TABLE compressed_data SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'device_id'
);

-- Add compression policies
SELECT add_compression_policy('compressed_data', INTERVAL '7 days');



BEGIN;
-- Hypertable with Continuous Aggregates

CREATE TABLE raw_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id INTEGER NOT NULL,
    value DOUBLE PRECISION
);

SELECT create_hypertable('raw_data', 'time');
COMMIT;


-- Create a continuous aggregate
CREATE MATERIALIZED VIEW daily_avg
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', time) AS day,
       sensor_id,
       AVG(value) AS avg_value
FROM raw_data
GROUP BY day, sensor_id;

-- Add policy to refresh continuous aggregate
SELECT add_continuous_aggregate_policy('daily_avg', start_offset => INTERVAL '7 days', end_offset => INTERVAL '2 days', schedule_interval => INTERVAL '3 days');

BEGIN;
-- Hypertable with Advanced Indexing

CREATE TABLE indexed_data (
    time TIMESTAMPTZ NOT NULL,
    user_id INTEGER NOT NULL,
    action TEXT,
    metadata JSONB
);

SELECT create_hypertable('indexed_data', 'time');

-- Create an index on user_id and time
CREATE INDEX ON indexed_data (user_id, time);

-- Create a GIN index on the JSONB metadata column
CREATE INDEX ON indexed_data USING GIN (metadata);



-- Create a table without a time column
CREATE TABLE indexed_data_without_time (
    user_id INTEGER NOT NULL,
    action TEXT,
    metadata JSONB
);

-- Convert to hypertable using space partitioning
SELECT create_hypertable('indexed_data_without_time', 'user_id', if_not_exists => TRUE);

-- Create a B-Tree index on user_id
CREATE INDEX idx_user_id ON indexed_data_without_time (user_id);

-- Create a GIN index on the JSONB metadata column
CREATE INDEX idx_metadata_gin ON indexed_data_without_time USING GIN (metadata);
-- Insert data into the hypertable
INSERT INTO indexed_data_without_time (user_id, action, metadata)
VALUES
    (1, 'login', '{"device": "mobile"}'),
    (2, 'logout', '{"device": "desktop"}'),
    (1, 'update_profile', '{"field": "email"}');


-- Hypertable with Retention Policies

-- Step 1: Redefine the table with a composite primary key
CREATE TABLE historical_data (
    time TIMESTAMPTZ NOT NULL,
    event_id SERIAL NOT NULL,
    event_type TEXT,
    event_details TEXT,
    PRIMARY KEY (time, event_id)
);

-- Step 2: Convert the table to a hypertable
SELECT create_hypertable('historical_data', 'time');

-- Step 3: Add a retention policy to drop data older than 30 days
SELECT add_retention_policy('historical_data', INTERVAL '30 days');

INSERT INTO historical_data (time, event_type, event_details)
VALUES 
    (NOW(), 'login', 'User logged in from IP 192.168.1.1'),
    (NOW(), 'logout', 'User logged out'),
    (NOW(), 'update', 'User updated profile information');


-- primary partition as something other than time

CREATE TABLE sensor_data_partitioned (
    sensor_id INTEGER NOT NULL,
    time TIMESTAMPTZ NOT NULL,
    value DOUBLE PRECISION,
    location TEXT,
    PRIMARY KEY (sensor_id, time)  -- Define a composite primary key
);
-- Create the hypertable with primary time and secondary sensor_id partitioning
SELECT create_hypertable('sensor_data_partitioned', 'time', 'sensor_id', number_partitions => 4);
-- Insert some data
INSERT INTO sensor_data_partitioned (time, sensor_id, value, location) VALUES
('2024-01-01 00:00:00', 1, 23.5, 'Room A'),
('2024-01-01 00:00:00', 2, 22.1, 'Room B'),
('2024-01-02 00:00:00', 1, 24.3, 'Room A'),
('2024-01-02 00:00:00', 2, 23.8, 'Room B');


-- compressed data with different column as partitioner


-- Step 1: Create the table with primary device_id and secondary time partitioning
CREATE TABLE device_data (
    device_id INTEGER NOT NULL,
    time TIMESTAMPTZ NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (device_id, time)
);

-- Step 2: Create the hypertable
SELECT create_hypertable('device_data', 'device_id', 'time', number_partitions => 4);

COMMIT;

-- Step 3: Enable compression
ALTER TABLE device_data SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'time'
);

-- Step 4: Add compression policy with compress_after for integer partitioning
SELECT add_compression_policy('device_data', compress_after => 5);

-- Continuos Aggregation + Compression
BEGIN;

-- Create the hypertable with time column
CREATE TABLE temperature_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION
);

-- Convert the table to a hypertable with `time` as the primary partitioning column
SELECT create_hypertable('temperature_data', 'time');

-- Insert sample data

INSERT INTO temperature_data (time, sensor_id, temperature)
VALUES
    ('2024-07-01 10:00:00', 1, 22.5),
    ('2024-07-01 11:00:00', 1, 23.0),
    ('2024-07-02 10:00:00', 2, 19.5),
    ('2024-07-02 11:00:00', 2, 20.0);


COMMIT;

-- Create a continuous aggregate
CREATE MATERIALIZED VIEW daily_temperature_avg
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', time) AS day,
       sensor_id,
       AVG(temperature) AS avg_temperature
FROM temperature_data
GROUP BY day, sensor_id;

-- Add policy to refresh continuous aggregate
SELECT add_continuous_aggregate_policy('daily_temperature_avg', start_offset => INTERVAL '7 days', end_offset => INTERVAL '2 days', schedule_interval => INTERVAL '3 days');


-- Enable compression on the hypertable
ALTER TABLE temperature_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id'
);


-- Add a compression policy to compress data older than 7 days
SELECT add_compression_policy('temperature_data', INTERVAL '7 days');

BEGIN;

-- advanced indexing and continuous aggregates 

-- Create a table with a time column
CREATE TABLE indexed_data_with_time (
    time TIMESTAMPTZ NOT NULL,
    user_id INTEGER NOT NULL,
    action TEXT,
    metadata JSONB
);

-- Convert to hypertable using time dimension
SELECT create_hypertable('indexed_data_with_time', 'time');

-- Create a B-Tree index on user_id and time
CREATE INDEX idx_user_id_time ON indexed_data_with_time (user_id, time);

-- Create a GIN index on the JSONB metadata column
CREATE INDEX idx_metadata_gin_1 ON indexed_data_with_time USING GIN (metadata);

COMMIT;
-- Create a continuous aggregate

CREATE MATERIALIZED VIEW user_action_counts
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', time) AS day,
       user_id,
       COUNT(action) AS action_count
FROM indexed_data_with_time
GROUP BY day, user_id;

-- Add a policy to refresh the continuous aggregate
SELECT add_continuous_aggregate_policy('user_action_counts', 
    start_offset => INTERVAL '7 days', 
    end_offset => INTERVAL '3 days',
    schedule_interval => INTERVAL '2 days');

BEGIN;
-- Insert sample data into indexed_data_with_time
INSERT INTO indexed_data_with_time (time, user_id, action, metadata)
VALUES
    ('2024-07-23 08:00:00+00', 1, 'login', '{"device": "mobile", "location": "NY"}'),
    ('2024-07-23 09:00:00+00', 2, 'logout', '{"device": "desktop", "location": "LA"}'),
    ('2024-07-23 10:00:00+00', 3, 'purchase', '{"device": "tablet", "location": "SF", "amount": 150}'),
    ('2024-07-23 11:00:00+00', 1, 'login', '{"device": "mobile", "location": "NY"}'),
    ('2024-07-23 12:00:00+00', 2, 'logout', '{"device": "desktop", "location": "LA"}'),
    ('2024-07-23 13:00:00+00', 3, 'purchase', '{"device": "tablet", "location": "SF", "amount": 200}');



--  advance indexing and compression
-- Create a table with a time column
CREATE TABLE compressed_data_with_time (
    time TIMESTAMPTZ NOT NULL,
    user_id INTEGER NOT NULL,
    action TEXT,
    metadata JSONB
);

-- Convert to hypertable using time dimension
SELECT create_hypertable('compressed_data_with_time', 'time');

-- Create a B-Tree index on user_id and time
CREATE INDEX idx_user_id_time_compressed ON compressed_data_with_time (user_id, time);

-- Create a GIN index on the JSONB metadata column
CREATE INDEX idx_metadata_gin_compressed ON compressed_data_with_time USING GIN (metadata);

-- Insert sample data into compressed_data_with_time
INSERT INTO compressed_data_with_time (time, user_id, action, metadata)
VALUES
    ('2024-07-23 08:00:00+00', 1, 'login', '{"device": "mobile", "location": "NY"}'),
    ('2024-07-23 09:00:00+00', 2, 'logout', '{"device": "desktop", "location": "LA"}'),
    ('2024-07-23 10:00:00+00', 3, 'purchase', '{"device": "tablet", "location": "SF", "amount": 150}'),
    ('2024-07-23 11:00:00+00', 1, 'login', '{"device": "mobile", "location": "NY"}'),
    ('2024-07-23 12:00:00+00', 2, 'logout', '{"device": "desktop", "location": "LA"}'),
    ('2024-07-23 13:00:00+00', 3, 'purchase', '{"device": "tablet", "location": "SF", "amount": 200}');

    COMMIT;
-- Enable compression
ALTER TABLE compressed_data_with_time SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_id'
);

-- Add a compression policy
SELECT add_compression_policy('compressed_data_with_time', INTERVAL '7 days');

BEGIN;

--  advance indexing,compression and continuous aggregates

-- Create a table with a time column
CREATE TABLE indexed_compressed_data_with_time (
    time TIMESTAMPTZ NOT NULL,
    user_id INTEGER NOT NULL,
    action TEXT,
    metadata JSONB
);

-- Convert to hypertable using time dimension
SELECT create_hypertable('indexed_compressed_data_with_time', 'time');

-- Create a B-Tree index on user_id and time
CREATE INDEX idx_user_id_time_indexed ON indexed_compressed_data_with_time (user_id, time);

-- Create a GIN index on the JSONB metadata column
CREATE INDEX idx_metadata_gin_indexed ON indexed_compressed_data_with_time USING GIN (metadata);

COMMIT;

-- Enable compression
ALTER TABLE indexed_compressed_data_with_time SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_id'
);

-- Add a compression policy
SELECT add_compression_policy('indexed_compressed_data_with_time', INTERVAL '7 days');

-- Create a continuous aggregate
CREATE MATERIALIZED VIEW user_action_daily_avg
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', time) AS day,
       user_id,
       COUNT(action) AS action_count,
       AVG((metadata->>'value')::DOUBLE PRECISION) AS avg_value
FROM indexed_compressed_data_with_time
WHERE metadata ? 'value'
GROUP BY day, user_id;

-- Add a policy to refresh the continuous aggregate
SELECT add_continuous_aggregate_policy('user_action_daily_avg',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '3 days',
    schedule_interval => INTERVAL '2 days');

BEGIN;

-- Insert sample data
INSERT INTO indexed_compressed_data_with_time (time, user_id, action, metadata)
VALUES
    ('2024-07-23 10:00:00+00', 1, 'login', '{"value": 10}'),
    ('2024-07-23 11:00:00+00', 2, 'logout', '{"value": 20}'),
    ('2024-07-23 12:00:00+00', 1, 'update_profile', '{"value": 30}');


-- retention policy with space complexity

CREATE TABLE sensor_data_v2 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);
-- Convert the table to a hypertable


SELECT create_hypertable('sensor_data_v2', 'time', 'device_id', number_partitions=>4);

-- Add a retention policy to drop data older than 30 days
SELECT add_retention_policy('sensor_data_v2', INTERVAL '30 days');


INSERT INTO sensor_data_v2 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);
-- retention policies and advanced indexing

CREATE TABLE sensor_data_1 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_1', 'time');
SELECT add_retention_policy('sensor_data_1', INTERVAL '30 days');
CREATE INDEX idx_sensor_data_1_temperature ON sensor_data_1 (temperature);
INSERT INTO sensor_data_1 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);

-- retention policies and continuous aggregates


CREATE TABLE sensor_data_2 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_2', 'time');
SELECT add_retention_policy('sensor_data_2', INTERVAL '30 days');
COMMIT;

CREATE MATERIALIZED VIEW sensor_data_2_daily WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', time) AS day,
    device_id,
    AVG(temperature) AS avg_temperature,
    AVG(humidity) AS avg_humidity
FROM 
    sensor_data_2
GROUP BY 
    day, device_id;

SELECT add_continuous_aggregate_policy('sensor_data_2_daily', start_offset => INTERVAL '1 month', end_offset => INTERVAL '1 day', schedule_interval => INTERVAL '1 day');

BEGIN;

INSERT INTO sensor_data_2 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


-- retention policies and compression

CREATE TABLE sensor_data_3 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_3', 'time');

SELECT add_retention_policy('sensor_data_3', INTERVAL '30 days');

INSERT INTO sensor_data_3 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


COMMIT;

ALTER TABLE sensor_data_3 SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'device_id'
);

SELECT add_compression_policy('sensor_data_3', INTERVAL '14 days');


BEGIN;

-- retention policies and space partitioning

CREATE TABLE sensor_data_4 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_4', 'time', 'device_id', number_partitions => 6);
SELECT add_retention_policy('sensor_data_4', INTERVAL '30 days');
INSERT INTO sensor_data_4 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);

-- retention policies, advanced indexing and continuous aggregates

CREATE TABLE sensor_data_5 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_5', 'time');
SELECT add_retention_policy('sensor_data_5', INTERVAL '30 days');
CREATE INDEX idx_sensor_data_5_temperature ON sensor_data_5 (temperature);

COMMIT;

CREATE MATERIALIZED VIEW sensor_data_5_daily WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', time) AS day,
    device_id,
    AVG(temperature) AS avg_temperature,
    AVG(humidity) AS avg_humidity
FROM 
    sensor_data_5
GROUP BY 
    day, device_id;

SELECT add_continuous_aggregate_policy('sensor_data_5_daily', start_offset => INTERVAL '1 month', end_offset => INTERVAL '1 day', schedule_interval => INTERVAL '1 day');

BEGIN;

INSERT INTO sensor_data_5 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


-- retention policies, advanced indexing and compression

CREATE TABLE sensor_data_6 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_6', 'time');
SELECT add_retention_policy('sensor_data_6', INTERVAL '30 days');
CREATE INDEX idx_sensor_data_6_temperature ON sensor_data_6 (temperature);

COMMIT;

ALTER TABLE sensor_data_6 SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'device_id'
);

SELECT add_compression_policy('sensor_data_6', INTERVAL '14 days');

BEGIN;

INSERT INTO sensor_data_6 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


-- retention policies, advanced indexing and space partitioning

CREATE TABLE sensor_data_7 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_7', 'time', 'device_id',number_partitions=>2);
SELECT add_retention_policy('sensor_data_7', INTERVAL '30 days');
CREATE INDEX idx_sensor_data_7_temperature ON sensor_data_7 (temperature);
INSERT INTO sensor_data_7 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


-- retention policies, continuous agggregates and compression

CREATE TABLE sensor_data_8 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_8', 'time');
SELECT add_retention_policy('sensor_data_8', INTERVAL '30 days');

COMMIT;

CREATE MATERIALIZED VIEW sensor_data_8_daily  WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', time) AS day,
    device_id,
    AVG(temperature) AS avg_temperature,
    AVG(humidity) AS avg_humidity
FROM 
    sensor_data_8
GROUP BY 
    day, device_id;

SELECT add_continuous_aggregate_policy('sensor_data_8_daily', start_offset => INTERVAL '1 month', end_offset => INTERVAL '1 day', schedule_interval => INTERVAL '1 day');


ALTER TABLE sensor_data_8 SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'device_id'
);

SELECT add_compression_policy('sensor_data_8', INTERVAL '14 days');

BEGIN;

INSERT INTO sensor_data_8 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


-- retention policies, continuous aggregates and space partitioning

CREATE TABLE sensor_data_9 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_9', 'time', 'device_id', number_partitions=>7);
SELECT add_retention_policy('sensor_data_9', INTERVAL '30 days');

COMMIT;

CREATE MATERIALIZED VIEW sensor_data_9_daily WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', time) AS day,
    device_id,
    AVG(temperature) AS avg_temperature,
    AVG(humidity) AS avg_humidity
FROM 
    sensor_data_9
GROUP BY 
    day, device_id;

SELECT add_continuous_aggregate_policy('sensor_data_9_daily', start_offset => INTERVAL '1 month', end_offset => INTERVAL '1 day', schedule_interval => INTERVAL '1 day');

BEGIN;

INSERT INTO sensor_data_9 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


-- retention policies, compression and space partitioning
CREATE TABLE sensor_data_10 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_10', 'time', 'device_id', number_partitions =>5);
SELECT add_retention_policy('sensor_data_10', INTERVAL '30 days');

COMMIT;

ALTER TABLE sensor_data_10 SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'device_id'
);

SELECT add_compression_policy('sensor_data_10', INTERVAL '14 days');

BEGIN;

INSERT INTO sensor_data_10 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);


-- retention policies, continuous aggregates, compression,space partitioning and advanced indexing
CREATE TABLE sensor_data_11 (
    time TIMESTAMPTZ NOT NULL,
    device_id INTEGER NOT NULL,
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    PRIMARY KEY (time, device_id)
);

SELECT create_hypertable('sensor_data_11', 'time', 'device_id', number_partitions =>4);

SELECT add_retention_policy('sensor_data_11', INTERVAL '30 days');

COMMIT;

CREATE MATERIALIZED VIEW sensor_data_11_daily WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', time) AS day,
    device_id,
    AVG(temperature) AS avg_temperature,
    AVG(humidity) AS avg_humidity
FROM 
    sensor_data_11
GROUP BY 
    day, device_id;

SELECT add_continuous_aggregate_policy('sensor_data_11_daily', start_offset => INTERVAL '1 month', end_offset => INTERVAL '1 day', schedule_interval => INTERVAL '1 day');

ALTER TABLE sensor_data_11 SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'device_id'
);

SELECT add_compression_policy('sensor_data_11', INTERVAL '14 days');

BEGIN;

CREATE INDEX idx_sensor_data_11_temperature ON sensor_data_11 (temperature);
INSERT INTO sensor_data_11 (time, device_id, temperature, humidity)
VALUES 
    (NOW(), 1, 22.5, 60.0),
    (NOW(), 2, 23.0, 55.0),
    (NOW(), 3, 21.5, 65.0);

COMMIT;

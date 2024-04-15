-- Connect to DB
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_raster;

-- Tables
CREATE TABLE IF NOT EXISTS "map_routes" (
    gid serial PRIMARY KEY,
    id varchar(200),
    popis varchar(200),
    rokzameren varchar(200),
    zkratka varchar(200),
    geom geometry('LINESTRINGZM', 5514, 4)
);

CREATE TABLE IF NOT EXISTS "osm_data_index" (
    relcislo int PRIMARY KEY,
    id varchar(6),
    nazevtrasy varchar(200)
);

CREATE TABLE IF NOT EXISTS "osm_rails" (
    gid serial PRIMARY KEY,
    relcislo int,
    geom geometry('LINESTRING', 4326, 2),
    CONSTRAINT fk_relcislo_osm
        FOREIGN KEY(relcislo)
            REFERENCES osm_data_index(relcislo)
);

CREATE TABLE IF NOT EXISTS "processed_routes" (
    relcislo int PRIMARY KEY,
    geom geometry('MULTILINESTRINGZM', 5514, 4),
    CONSTRAINT fk_relcislo_pr
        FOREIGN KEY(relcislo)
            REFERENCES osm_data_index(relcislo)
);

CREATE TABLE IF NOT EXISTS "processed_routes_line" (
    relcislo int PRIMARY KEY,
    geom geometry('LINESTRINGZ', 5514, 4),
    CONSTRAINT fk_relcislo_prline
        FOREIGN KEY(relcislo)
            REFERENCES osm_data_index(relcislo)
);

CREATE TABLE IF NOT EXISTS "osm_ways" (
    id integer PRIMARY KEY,
    electrified varchar(20),
    voltage integer,
    gauge varchar(20),
    maxspeed integer,
    tracks integer,
    usage varchar(20),
    geom geometry('LINESTRING', 4326, 2)
);

CREATE TABLE IF NOT EXISTS "all_stations" (
    id numeric PRIMARY KEY,
    name varchar(254),
    geom geometry('POINT', 4326, 2)
);

CREATE TABLE IF NOT EXISTS "processed_routes_tags" (
    relcislo int,
    tag_name varchar(20),
    tag_value varchar(20),
    tag_portion double precision,
    CONSTRAINT fk_relcislo_tags
        FOREIGN KEY(relcislo)
            REFERENCES osm_data_index(relcislo)
);

-- Login tables
CREATE TABLE IF NOT EXISTS "users" (
	"id" SERIAL PRIMARY KEY CHECK ("id" >= 0),
	"email" VARCHAR(249) UNIQUE NOT NULL,
	"password" VARCHAR(255) NOT NULL,
	"username" VARCHAR(100) DEFAULT NULL,
	"status" SMALLINT NOT NULL DEFAULT '0' CHECK ("status" >= 0),
	"verified" SMALLINT NOT NULL DEFAULT '0' CHECK ("verified" >= 0),
	"resettable" SMALLINT NOT NULL DEFAULT '1' CHECK ("resettable" >= 0),
	"roles_mask" INTEGER NOT NULL DEFAULT '0' CHECK ("roles_mask" >= 0),
	"registered" INTEGER NOT NULL CHECK ("registered" >= 0),
	"last_login" INTEGER DEFAULT NULL CHECK ("last_login" >= 0),
	"force_logout" INTEGER NOT NULL DEFAULT '0' CHECK ("force_logout" >= 0)
);

CREATE TABLE IF NOT EXISTS "users_confirmations" (
	"id" SERIAL PRIMARY KEY CHECK ("id" >= 0),
	"user_id" INTEGER NOT NULL CHECK ("user_id" >= 0),
	"email" VARCHAR(249) NOT NULL,
	"selector" VARCHAR(16) UNIQUE NOT NULL,
	"token" VARCHAR(255) NOT NULL,
	"expires" INTEGER NOT NULL CHECK ("expires" >= 0)
);
CREATE INDEX IF NOT EXISTS "email_expires" ON "users_confirmations" ("email", "expires");
CREATE INDEX IF NOT EXISTS "user_id" ON "users_confirmations" ("user_id");

CREATE TABLE IF NOT EXISTS "users_remembered" (
	"id" BIGSERIAL PRIMARY KEY CHECK ("id" >= 0),
	"user" INTEGER NOT NULL CHECK ("user" >= 0),
	"selector" VARCHAR(24) UNIQUE NOT NULL,
	"token" VARCHAR(255) NOT NULL,
	"expires" INTEGER NOT NULL CHECK ("expires" >= 0)
);
CREATE INDEX IF NOT EXISTS "user" ON "users_remembered" ("user");

CREATE TABLE IF NOT EXISTS "users_resets" (
	"id" BIGSERIAL PRIMARY KEY CHECK ("id" >= 0),
	"user" INTEGER NOT NULL CHECK ("user" >= 0),
	"selector" VARCHAR(20) UNIQUE NOT NULL,
	"token" VARCHAR(255) NOT NULL,
	"expires" INTEGER NOT NULL CHECK ("expires" >= 0)
);
CREATE INDEX IF NOT EXISTS "user_expires" ON "users_resets" ("user", "expires");

CREATE TABLE IF NOT EXISTS "users_throttling" (
	"bucket" VARCHAR(44) PRIMARY KEY,
	"tokens" REAL NOT NULL CHECK ("tokens" >= 0),
	"replenished_at" INTEGER NOT NULL CHECK ("replenished_at" >= 0),
	"expires_at" INTEGER NOT NULL CHECK ("expires_at" >= 0)
);
CREATE INDEX IF NOT EXISTS "expires_at" ON "users_throttling" ("expires_at");

-- Triggers, functions and views
CREATE OR REPLACE FUNCTION make_processed_route_line() 
   RETURNS TRIGGER 
   LANGUAGE PLPGSQL
AS $$
BEGIN
	DELETE FROM processed_routes_line WHERE relcislo = new.relcislo;	
	INSERT INTO processed_routes_line (relcislo, geom)
   	SELECT relcislo, ST_LineMerge(geom) AS geom
	FROM processed_routes WHERE relcislo = new.relcislo;
	RETURN NEW;
END;
$$;

CREATE TRIGGER processed_insert
AFTER INSERT
ON processed_routes
FOR EACH ROW
EXECUTE PROCEDURE make_processed_route_line();

CREATE OR REPLACE VIEW even_processed_routes_line AS
SELECT
    relcislo, ST_MakeLine(ST_LineInterpolatePoints(ST_Transform(geom, 4326),
    (10/ST_Length(ST_Transform(geom, 4326)::geography)), TRUE)) AS geom
FROM processed_routes_line
GROUP BY relcislo;

CREATE OR REPLACE FUNCTION get_route_line_ways(p_relcislo int)
   RETURNS TABLE (way_id int, relcislo int, start_order int, end_order int)
AS
$BODY$
	SELECT way_id, relcislo, min(index) AS start_order, max(index) AS end_order FROM (
		SELECT *, count(is_reset) OVER (ORDER BY index) AS grp FROM (
			SELECT *, CASE WHEN LAG(maxspeed) OVER (ORDER BY index) <> maxspeed THEN 1 END AS is_reset FROM (
				SELECT index, dpoints.geom, dpoints.relcislo,
				CASE
					WHEN LAG(closest.maxspeed) OVER (ORDER BY index) <> closest.maxspeed AND
					LAG(closest.maxspeed) OVER (ORDER BY index) = LEAD(closest.maxspeed) OVER (ORDER BY index)
						THEN LAG(closest.id) OVER (ORDER BY index)
						ELSE closest.id
					END AS way_id,
				CASE
					WHEN LAG(closest.maxspeed) OVER (ORDER BY index) <> closest.maxspeed
					AND LAG(closest.maxspeed) OVER (ORDER BY index) = LEAD(closest.maxspeed) OVER (ORDER BY index)
						THEN LAG(closest.maxspeed) OVER (ORDER BY index)
						ELSE closest.maxspeed
					END AS maxspeed
				FROM
				(
					SELECT (ST_DumpPoints(geom)).path[1]-1 AS index, ST_Force2D((ST_DumpPoints(ST_Transform(geom, 4326))).geom) AS geom, relcislo
					FROM processed_routes_line
					WHERE relcislo = p_relcislo
				) AS dpoints
				JOIN LATERAL
				(
					SELECT id, maxspeed, geom
					FROM osm_ways
					WHERE maxspeed IS NOT NULL
					ORDER BY dpoints.geom <-> osm_ways.geom
					LIMIT 1
				) AS closest
				ON true
			) AS indexed
		) AS speedsplit
	) AS grouped
	GROUP BY way_id, relcislo, grp
	ORDER BY min(index);
$BODY$
LANGUAGE SQL;

CREATE OR REPLACE FUNCTION get_even_route_line_ways(p_relcislo int)
   RETURNS TABLE (way_id int, relcislo int, start_order int, end_order int)
AS
$BODY$
	SELECT way_id, relcislo, min(index) AS start_order, max(index) AS end_order FROM (
		SELECT *, count(is_reset) OVER (ORDER BY index) AS grp FROM (
			SELECT *, CASE WHEN LAG(maxspeed) OVER (ORDER BY index) <> maxspeed THEN 1 END AS is_reset FROM (
				SELECT index, dpoints.geom, dpoints.relcislo,
				CASE
					WHEN LAG(closest.maxspeed) OVER (ORDER BY index) <> closest.maxspeed AND
					LAG(closest.maxspeed) OVER (ORDER BY index) = LEAD(closest.maxspeed) OVER (ORDER BY index)
						THEN LAG(closest.id) OVER (ORDER BY index)
						ELSE closest.id
					END AS way_id,
				CASE
					WHEN LAG(closest.maxspeed) OVER (ORDER BY index) <> closest.maxspeed
					AND LAG(closest.maxspeed) OVER (ORDER BY index) = LEAD(closest.maxspeed) OVER (ORDER BY index)
						THEN LAG(closest.maxspeed) OVER (ORDER BY index)
						ELSE closest.maxspeed
					END AS maxspeed
				FROM
				(
					SELECT (ST_DumpPoints(geom)).path[1]-1 AS index, ST_Force2D((ST_DumpPoints(geom)).geom) AS geom, relcislo
					FROM even_processed_routes_line
					WHERE relcislo = p_relcislo
				) AS dpoints
				JOIN LATERAL
				(
					SELECT id, maxspeed, geom
					FROM osm_ways
					WHERE maxspeed IS NOT NULL
					ORDER BY dpoints.geom <-> osm_ways.geom
					LIMIT 1
				) AS closest
				ON true
			) AS indexed
		) AS speedsplit
	) AS grouped
	GROUP BY way_id, relcislo, grp
	ORDER BY min(index);
$BODY$
LANGUAGE SQL;

CREATE OR REPLACE FUNCTION generate_route_tags() 
   RETURNS TRIGGER 
   LANGUAGE PLPGSQL
AS $$
BEGIN
	DELETE FROM processed_routes_tags WHERE relcislo = new.relcislo;
	INSERT INTO processed_routes_tags(relcislo, tag_name, tag_value, tag_portion)
	SELECT new.relcislo AS relcislo, 'electrified' AS "tag_name",
	electrified AS tag_value, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS tag_portion
	FROM get_route_line_ways(new.relcislo) AS rlw
	JOIN osm_ways ON rlw.way_id = osm_ways.id
	GROUP BY electrified
	ORDER BY tag_portion DESC;
	UPDATE processed_routes_tags SET tag_value = 'no' WHERE tag_value IS NULL;
	RETURN NEW;
END;
$$;

CREATE TRIGGER route_tags_gen
AFTER INSERT OR UPDATE
ON processed_routes_line
FOR EACH ROW
EXECUTE PROCEDURE generate_route_tags();

# Mapster DB
> Tento repositář si klade za cíl popsat aktuální stav aplikační databáze a ukázat, jak takovou databázi vytvořit.

## Upozornění
Než se pokusíte databázi sestavit celou znovu, zvažte stažení hotového obrazu databáze a obnovení pomocí nástroje `pg_restore`. Bude to **znatelně** rychlejší pro Vás i databázový server. Schéma je relativně rozsáhlé a toto bych nikomu nepřál sestavovat ručně, pokud to jde jinak.

## Tvorba DB

```sql
CREATE DATABASE map_data WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'en_US.utf8';
```

## Po připojení do databáze

### Povolení PostGISu
> Toto jsou databázová rozšíření, která je nutné povolit. Bez nich by nebylo možné v databázi mít poziční data. Pokud nejsou rozšíření nainstalována, je před spuštěním těchto příkazu nutné instalaci provést.

```sql
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_raster;
```

### Vytvoření tabulek pro mapové objekty
> Toto je seznam všech tabulek, které se využívají v databázi pro ukládání pozičních dat a přidružených metadat.

```sql
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
```

### Vytvoření tabulek pro správu uživatelů
Toto je seznam všech tabulek, které se využívají v databázi pro ukládání uživatelských dat (přihlašovací systém).

Zdroj: https://github.com/delight-im/PHP-Auth/blob/master/Database/PostgreSQL.sql

```sql
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
```

### Trigger pro převedení zpracovaných tratí na typ `LineStringZ`
Při nahrávání zpracovaných tratí se převod provede v databázi.

```sql
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
```

### Vytvoření ekvidistantních tratí (view)
Tento databázový pohled nabízí zpracované tratě z tabulky `processed_routes_line` v podobě, kde jsou po sobě jdoucí body ve stejné vzdálenosti od sebe.

```sql
CREATE OR REPLACE VIEW even_processed_routes_line AS
SELECT
    relcislo, ST_MakeLine(ST_LineInterpolatePoints(ST_Transform(geom, 4326),
    (10/ST_Length(ST_Transform(geom, 4326)::geography)), TRUE)) AS geom
FROM processed_routes_line
GROUP BY relcislo;
```

### Funkce pro získávání metadat
Tyto funkce slouží k přiřazení kolejových segmentů z OSM k existujícím tratím tak, aby bylo možné vyčítat metadata.

```sql
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
```

### Trigger pro generování metadat formou souhrných statistik
Tento trigger slouží pro naplnění tabulky s metadaty po každé změně tabulky se zpracovanými tratěmi.

```sql
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
```

### Import surových dat
Nyní je nutné importovat surová data od SŽ. Jsou uloženy v zip souboru a níže je postup, jak je rovnou nahrát do databáze.

```console
unzip raw-data/osykoleji_3d-corrected.zip -d /tmp/
chmod +x import-scripts/import-shapefile-simplify.sh
DBHOST=localhost DBPORT=5432 DBNAME=railway_mapdb_puretest DBUSER=postgres ./import-scripts/import-shapefile-simplify.sh /tmp/221102_osy_koleji_podle_podkladu.shp map_routes
rm /tmp/221102_osy_koleji_podle_podkladu.*
```

### Stažení OSM dat
Tento proces automaticky provede stažení všech potřebných dat z databáze OSM. Je akorát nutné upravit konfigurační soubor `config.py`.

```console
cp import-scripts/overpass/config.py.template import-scripts/overpass/config.py
nano import-scripts/overpass/config.py
```

Po změně konfigurace se nainstalují závislosti. Poslední příkaz je nutné spustit vícekrát a provést všechny kroky (1️⃣, 2️⃣ a 3️⃣).

```console
python -m venv venv
source venv/bin/activate
pip install -r import-scripts/overpass/requirements.txt
python import-scripts/overpass/osm-overpass.py
```

### Import manuálně zpracovaných tratí
Nyní je nutné importovat manuálně zpracované tratě (spojení dat SŽ a OSM). Jsou uloženy v zip souboru a níže je postup, jak je rovnou nahrát do databáze.

**POZOR:** Import může být pomalejší, protože se při přidávání tratí zároveň probíhají triggery (pro konverzi a pro získání souhrných metadat) 

```console
unzip raw-data/processed_routes.zip -d /tmp/
chmod +x import-scripts/import-shapefile.sh
DBHOST=localhost DBPORT=5432 DBNAME=railway_mapdb_puretest DBUSER=postgres ./import-scripts/import-shapefile.sh /tmp/processed_routes.shp processed_routes
rm /tmp/processed_routes.*
```

### Mapování stanic na tratě (view)
Tyto dva pohledy tvoří mapování stanic na indexy bodů tratí. Jsou dva, protože jedna verze je pro ekvidistantní varianty tratí.

```sql
CREATE OR REPLACE VIEW station_relation AS
SELECT DISTINCT ON(relcislo, station_id) relcislo, station_id, index AS station_order, geom
FROM
(
	SELECT index, dpoints.geom, relcislo, all_stations.name, id AS station_id, ST_Distance(dpoints.geom, all_stations.geom) AS dist
	FROM 
	(
		SELECT (ST_DumpPoints(geom)).path[1]-1 AS index, ST_Force2D((ST_DumpPoints(ST_Transform(geom, 4326))).geom) AS geom, relcislo
		FROM processed_routes_line
	) AS dpoints, all_stations
	WHERE ST_DWithin(dpoints.geom, all_stations.geom, 0.001)
) AS candidates
ORDER BY relcislo, station_id, dist, index;

CREATE OR REPLACE VIEW even_station_relation AS
SELECT DISTINCT ON(relcislo, station_id) relcislo, station_id, index AS station_order, geom
FROM
(
	SELECT index, dpoints.geom, dpoints.relcislo, all_stations.name, id AS station_id, ST_Distance(dpoints.geom, all_stations.geom) AS dist
	FROM
	(
		SELECT (ST_DumpPoints(geom)).path[1]-1 AS index, ST_Force2D((ST_DumpPoints(ST_Transform(geom, 4326))).geom) AS geom, relcislo
		FROM even_processed_routes_line
	) AS dpoints
	JOIN station_relation ON dpoints.relcislo = station_relation.relcislo
	JOIN all_stations ON station_relation.station_id = all_stations.id
) AS candidates
ORDER BY relcislo, station_id, dist, index;
```


### Materialized views s lepší elevací (Z coord - DTM)
Tyto dva materializované pohledy obsahují zpracované tratě (i v ekvidistantní variantě), kde byly výškové profily nahrazeny daty z datasetu EU DTM (přesnější).

Nejdříve je nutné stáhnout data [EU DTM](https://opentopography.s3.sdsc.edu/minio/raster/EU_DTM/EU_DTM_be/) (nejsou součástí, velký soubor) a umístit je do databáze jako tabulku `dtm_eu` pomocí příkazu níže.

```console
raster2pgsql -I -t 128x128 "dtm_elev.lowestmode_gedi.eml_mf_30m_0..0cm_2000..2018_eumap_epsg3035_v0.3_OT.tif" public.dtm_eu | psql -U postgres -d railway_mapdb -h localhost -p 5432
```

Patrně kvůli bugu ve starší verzi PostGISu (VŠB prod.) je nutné prohazovat souřadnice pro SRID 3035.

```sql
CREATE MATERIALIZED VIEW processed_routes_line_dtm AS
WITH points AS (
	-- Note: VŠB PostGIS is broken and needs coords in 3035 flipped
	SELECT relcislo, ST_DumpPoints(ST_FlipCoordinates(ST_Transform(geom, 3035))) AS pointdtm,
	ST_DumpPoints(geom) AS point5514
	FROM processed_routes_line
),
elev AS (
	SELECT relcislo, (pointdtm).path[1] AS index,
	AVG(
		CASE
		WHEN 
			ABS(
				ST_Z((pointdtm).geom) - ST_Value(dtm.rast,(pointdtm).geom)
			) > 100 OR ST_Z((pointdtm).geom) < 50
		THEN
			ST_Value(dtm.rast,(pointdtm).geom)
		ELSE
			ST_Z((pointdtm).geom)
		END
	) Over(PARTITION BY relcislo ORDER BY (pointdtm).path[1] rows between 10 preceding and current row) AS rolling_avg,
	ST_Z((pointdtm).geom) AS sz,
	ST_Value(dtm.rast,(pointdtm).geom) AS dtm,
	(point5514).geom AS point5514
	FROM points
	LEFT JOIN dtm_eu AS dtm ON ST_Intersects(dtm.rast, (pointdtm).geom)
	--WHERE relcislo IN (9190, 49010)
	ORDER BY relcislo, (pointdtm).path[1]
)
SELECT relcislo, ST_MakeLine(
	ST_Translate(
		ST_Force3DZ(ST_Force2D(point5514)), 
		0,
		0,
		rolling_avg
	)
	ORDER BY index
) AS geom
FROM elev
GROUP BY relcislo;

CREATE MATERIALIZED VIEW even_processed_routes_line_dtm AS
WITH points AS (
	-- Note: VŠB PostGIS is broken and needs coords in 3035 flipped
	SELECT relcislo, ST_DumpPoints(ST_FlipCoordinates(ST_Transform(geom, 3035))) AS pointdtm,
	ST_DumpPoints(geom) AS point5514
	FROM even_processed_routes_line
),
elev AS (
	SELECT relcislo, (pointdtm).path[1] AS index,
	AVG(
		CASE
		WHEN 
			ABS(
				ST_Z((pointdtm).geom) - ST_Value(dtm.rast,(pointdtm).geom)
			) > 100 OR ST_Z((pointdtm).geom) < 50
		THEN
			ST_Value(dtm.rast,(pointdtm).geom)
		ELSE
			ST_Z((pointdtm).geom)
		END
	) Over(PARTITION BY relcislo ORDER BY (pointdtm).path[1] rows between 10 preceding and current row) AS rolling_avg,
	ST_Z((pointdtm).geom) AS sz,
	ST_Value(dtm.rast,(pointdtm).geom) AS dtm,
	(point5514).geom AS point5514
	FROM points
	LEFT JOIN dtm_eu AS dtm ON ST_Intersects(dtm.rast, (pointdtm).geom)
	--WHERE relcislo IN (9190, 49010)
	ORDER BY relcislo, (pointdtm).path[1]
)
SELECT relcislo, ST_MakeLine(
	ST_Translate(
		ST_Force3DZ(ST_Force2D(point5514)), 
		0,
		0,
		rolling_avg
	)
	ORDER BY index
) AS geom
FROM elev
GROUP BY relcislo;
```

### Materialized views s lepší elevací (Z coord - DMR5G)
Tyto dva materializované pohledy obsahují zpracované tratě (i v ekvidistantní variantě), kde byly výškové profily nahrazeny daty z datasetu [DMR5G](https://geoportal.cuzk.cz/(S(eyg5jr5vwztgxt5ev2y3v1qp))/Default.aspx?lng=CZ&mode=TextMeta&side=vyskopis&metadataID=CZ-CUZK-DMR5G-V&mapid=8&menu=302) (přesnější).

O stažení a import dat se postará sada skriptů. Postup níže.

```console
cd import-scripts/
python cuzk-downloader.py
chmod +x *.sh
./process_output.sh
./rasterize_processed.sh
# Jednoduchá varianta
raster2pgsql -I -C -t 32x32 output/tiff/*.tiff public.dmr5g | psql -U postgres -d railway_mapdb -h localhost -p 5432 | grep -v INSERT
# Varianta se skriptem využívajícím více vláken
DBHOST=localhost DBPORT=5432 DBNAME=railway_mapdb_puretest DBUSER=postgres ./import_raster_threaded.sh
```

Pokud dojde k importu pomocí `threaded` skriptu, je nutné vytvořit index manuálně
```sql
CREATE INDEX ON "public"."dmr5g" USING gist (st_convexhull("rast"));
ANALYZE "public"."dmr5g";
SELECT AddRasterConstraints('public','dmr5g','rast',TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,FALSE,TRUE,TRUE,TRUE,TRUE,TRUE);
```

A nyní samotné pohledy.

```sql
CREATE MATERIALIZED VIEW processed_routes_line_dmr AS
WITH points AS (
	SELECT relcislo, (ST_DumpPoints(geom)).path[1] AS index, (ST_DumpPoints(geom)).geom AS trackp
	FROM processed_routes_line
	--WHERE relcislo IN (9190, 49010)
), rolling AS (
	SELECT 
		relcislo,
		points.index,
		trackp,
		AVG(
			ST_Value(dmr5g.rast, trackp)
		) Over(PARTITION BY relcislo ORDER BY points.index rows between 30 preceding and current row) AS rolling_z
	FROM points
	JOIN dmr5g ON dmr5g.rid = (
		SELECT MIN(rid) FROM dmr5g
		WHERE ST_Intersects(dmr5g.rast, trackp)
	)
)
SELECT relcislo, ST_Makeline(
	ST_Translate(
		ST_Force3DZ(ST_Force2D(trackp)), 
		0,
		0,
		rolling_z
	)
	ORDER BY index
) AS geom
FROM rolling
GROUP BY relcislo;

CREATE MATERIALIZED VIEW even_processed_routes_line_dmr AS
WITH points AS (
	SELECT relcislo, (ST_DumpPoints(geom)).path[1] AS index, (ST_DumpPoints(geom)).geom AS trackp,
	ST_Transform((ST_DumpPoints(geom)).geom, 5514) AS trackp5514
	FROM even_processed_routes_line
	--WHERE relcislo IN (9190, 49010)
), rolling AS (
	SELECT 
		relcislo,
		points.index,
		trackp,
		AVG(
			ST_Value(dmr5g.rast, trackp5514)
		) Over(PARTITION BY relcislo ORDER BY points.index rows between 30 preceding and current row) AS rolling_z
	FROM points
	JOIN dmr5g ON dmr5g.rid = (
		SELECT MIN(rid) FROM dmr5g
		WHERE ST_Intersects(dmr5g.rast, trackp5514)
	)
)
SELECT relcislo, ST_Makeline(
	ST_Translate(
		ST_Force3DZ(ST_Force2D(trackp)), 
		0,
		0,
		rolling_z
	)
	ORDER BY index
) AS geom
FROM rolling
GROUP BY relcislo;

```
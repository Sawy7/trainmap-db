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

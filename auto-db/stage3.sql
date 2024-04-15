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

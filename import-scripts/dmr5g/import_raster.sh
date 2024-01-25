#!/bin/sh
raster2pgsql -I -t 128x128 output/tiff/*.tiff public.dmr5g | PGPASSWORD=password psql -U postgres -d railway_mapdb -h localhost -p 5432 | grep -v INSERT

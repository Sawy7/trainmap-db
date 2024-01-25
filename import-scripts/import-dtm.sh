#!/bin/sh
raster2pgsql -I -t 128x128 "dtm_elev.lowestmode_gedi.eml_mf_30m_0..0cm_2000..2018_eumap_epsg3035_v0.3_OT.tif" public.dtm_eu | PGPASSWORD=password psql -U postgres -d railway_mapdb -h localhost -p 5432

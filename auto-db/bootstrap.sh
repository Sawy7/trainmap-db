#!/bin/sh
set -e

# Create the database
psql -U postgres -c "CREATE DATABASE railway_mapdb WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'en_US.utf8';"
cat ./stage1.sql | psql -U postgres -d railway_mapdb

# Import SZ data
unzip ./raw-data/osykoleji_3d-corrected.zip -d ./raw-data
shp2pgsql \
  -I \
  -a \
  -e \
  -S \
  -s 5514 \
  "./raw-data/221102_osy_koleji_podle_podkladu.shp" \
  map_routes 2> /dev/null \
  | psql -U postgres -d railway_mapdb

# Setup python venv
python3 -m venv venv
./venv/bin/pip install -r ./import-scripts/requirements.txt

# Download OSM data
cd ./import-scripts/overpass
cp ./config.py.template ./config.py
sed -i 's/^DBNAME=.*/DBNAME="railway_mapdb"/' ./config.py
sed -i 's/^DBUSER=.*/DBUSER="postgres"/' ./config.py
sed -i 's/^DBPASS=.*/DBPASS="mysecretpassword"/' ./config.py # TODO: make this non-hardcoded
sed -i 's/^DBHOST=.*/DBHOST="localhost"/' ./config.py
sed -i 's/^DBPORT=.*/DBPORT="5432"/' ./config.py
/data/venv/bin/python ./osm-overpass.py -a
cd /data

# Import processed data
unzip raw-data/processed_routes.zip -d ./raw-data
shp2pgsql \
  -I \
  -a \
  -e \
  -s 5514 \
  "./raw-data/processed_routes.shp" \
  processed_routes 2> /dev/null \
  | psql -U postgres -d railway_mapdb

# Remove extracted raw data
rm raw-data/*.dbf raw-data/*.prj raw-data/*.shp raw-data/*.shx raw-data/*.cpg raw-data/*.qmd

# Create some views
cat ./stage2.sql | psql -U postgres -d railway_mapdb

# Download DMR 5G
cd ./import-scripts/dmr5g
/data/venv/bin/python cuzk-downloader.py -y
bash ./process_output.sh
rm -rf /tmp/dmrtemp
bash ./rasterize_processed.sh
raster2pgsql -I -C -t 32x32 output/tiff/*.tiff public.dmr5g | psql -U postgres -d railway_mapdb | grep -v INSERT

# Go back to the root directory
cd /data

# Create some more views
cat ./stage3.sql | psql -U postgres -d railway_mapdb

# Remove Python venv
rm -rf ./venv

# Remove downloaded DMR 5G (assuming everything went well and rasters are in the DB now)
rm -rf import-scripts/dmr5g/output

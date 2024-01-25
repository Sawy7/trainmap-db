#!/bin/sh
###################################################################################
# PARAMETERS:                                                                     #
###################################################################################

if [ "$#" -ne 2 ]; then
    echo "ERROR: Specify shapefile name and output table name!"
    exit
fi
shapefileName=$1
routesTable=$2
srid="5514"

##################################################################################

shp2pgsql \
  -I \
  -a \
  -e \
  -S \
  -s $srid \
  "$shapefileName" \
  $routesTable 2> /dev/null \
  | psql -h $DBHOST -p $DBPORT -d $DBNAME -U $DBUSER

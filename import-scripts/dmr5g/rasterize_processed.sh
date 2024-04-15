#!/bin/bash

rasterize() {
    filename=$(basename -- "$1")
    noext="${filename%.*}"
    gdal_rasterize -3d -a_nodata 0 -tr 5 5 -co COMPRESS=DEFLATE "$1" "tiff/$noext".tiff > /dev/null 2>&1
    gdal_fillnodata.py "tiff/$noext".tiff "tiff/$noext"_fill.tiff > /dev/null 2>&1
    rm "tiff/$noext".tiff
    echo "$filename rasterized"
}

N=6
cd output
mkdir -p tiff
for i in $(ls shp/*.shp); do
  rasterize "$i" &

  if [[ $(jobs -r -p | wc -l) -ge $N ]]; then
    # now there are $N jobs already running, so wait here for any job
    # to be finished so there is a place to start next one.
    wait -n
  fi
done
wait

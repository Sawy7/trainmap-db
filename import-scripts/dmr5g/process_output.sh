#!/bin/bash

process_zip(){
  filename=$(basename -- "$1")
  noext="${filename%.*}"
  mkdir -p "$dmrtemp/$noext"
  unzip "$1" -d "$dmrtemp/$noext" > /dev/null
  las2las -i "$dmrtemp/$noext/$noext.laz" -o "$dmrtemp/$noext/$noext.las" --a_srs "EPSG:5514" > /dev/null 2>&1
  las2ogr -i "$dmrtemp/$noext/$noext.las" -o "$dmrtemp/$noext/$noext.shp" > /dev/null 2>&1
  rm "$dmrtemp/$noext/$noext.dbf"
  ogr2ogr "shp/$noext.shp" "$dmrtemp/$noext/$noext.shp" -a_srs "EPSG:5514" > /dev/null 2>&1
  rm -rf "$dmrtemp/$noext"
  echo "$filename processed"
}

dmrtemp="/tmp/dmrtemp"
N=$(nproc)
rm -rf "$dmrtemp"
mkdir -p "$dmrtemp"
cd output
mkdir -p shp
rm shp/*
for i in $(ls *.zip); do
  process_zip "$i" &

  if [[ $(jobs -r -p | wc -l) -ge $N ]]; then
    # now there are $N jobs already running, so wait here for any job
    # to be finished so there is a place to start next one.
    wait -n
  fi
done
wait

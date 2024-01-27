#!/bin/sh

import() {
    raster2pgsql -a -t 32x32 "$1" public.dmr5g_32 2> /dev/null \
    | PGPASSWORD=$DBPASS psql -U $DBUSER -d $DBNAME -h $DBHOST -p $DBPORT \
    | grep -v 'INSERT\|BEGIN\|COMMIT'
}

create_table() {
    raster2pgsql -p "$1" public.dmr5g_32 2> /dev/null \
    | PGPASSWORD=$DBPASS psql -U $DBUSER -d $DBNAME -h $DBHOST -p $DBPORT
}

N=12
parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
cd "$parent_path"
cd output/tiff
read -s -p "Please enter password for user $DBUSER: " DBPASS
create_table $(ls *.tiff | head -1)
for i in $(ls *.tiff); do
  import "$i" &

  if [[ $(jobs -r -p | wc -l) -ge $N ]]; then
    # now there are $N jobs already running, so wait here for any job
    # to be finished so there is a place to start next one.
    wait -n
  fi
done


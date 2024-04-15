#
# This Dockerfile is based on the official docker-postgis image
# Bumped to Bookworm (Debian 12) and added few custom packages
# https://github.com/postgis/docker-postgis/blob/6c43b39522f2de801ee83f09f631af1f0fbc2aad/16-3.4/Dockerfile
#

##################### Mostly original ##################### 
FROM postgres:16-bookworm

ENV POSTGIS_MAJOR 3

RUN apt-get update \
      && apt-cache showpkg postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
      && apt-get install -y --no-install-recommends \
           # ca-certificates: for accessing remote raster files;
           #   fix: https://github.com/postgis/docker-postgis/issues/307
           ca-certificates \
           wget \
           \
           postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
           postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR-scripts \
      && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /docker-entrypoint-initdb.d
RUN wget "https://raw.githubusercontent.com/postgis/docker-postgis/6c43b39522f2de801ee83f09f631af1f0fbc2aad/16-3.4/initdb-postgis.sh" -O /docker-entrypoint-initdb.d/10_postgis.sh
RUN wget "https://raw.githubusercontent.com/postgis/docker-postgis/6c43b39522f2de801ee83f09f631af1f0fbc2aad/16-3.4/update-postgis.sh" -O /usr/local/bin/update-postgis.sh
RUN chmod +x /usr/local/bin/update-postgis.sh
##################### Mostly original ##################### 

##################### Custom stuff bellow #################

# Set the working directory
RUN mkdir /data
WORKDIR /data

# Install dependencies tools
RUN apt-get update && apt-get install -y \
    gdal-bin \
    libgdal-dev \
    unzip \
    python3 \
    python3-venv \
    python3-wheel \
    g++ \
    libboost-all-dev \
    libgeotiff-dev \
    cmake \
    git \
    bzip2

# Build some more tools from PostGIS
RUN wget http://download.osgeo.org/postgis/source/postgis-3.4.2.tar.gz
RUN tar -xf postgis-3.4.2.tar.gz
RUN rm postgis-3.4.2.tar.gz
WORKDIR /data/postgis-3.4.2
RUN ./configure --without-protobuf
# shp2pgsql
WORKDIR /data/postgis-3.4.2/liblwgeom
RUN make
WORKDIR /data/postgis-3.4.2/loader
RUN make
RUN bash ../libtool --mode=install install -c shp2pgsql "/usr/local/bin/shp2pgsql"
# raster2pgsql
WORKDIR /data/postgis-3.4.2/raster/rt_core
RUN make
WORKDIR /data/postgis-3.4.2/raster/loader
RUN make
RUN make install
WORKDIR /data
RUN rm -rf postgis-3.4.2

# Pull and build laszip2
RUN wget https://download.osgeo.org/laszip/laszip-src-2.2.0.tar.bz2
RUN tar -xf laszip-src-2.2.0.tar.bz2
RUN rm laszip-src-2.2.0.tar.bz2
WORKDIR /data/laszip-src-2.2.0
RUN ./configure --prefix=/usr --libdir=/usr/lib/laszip --includedir=/usr/include/laszip
RUN make
RUN make install
WORKDIR /data
RUN rm -rf laszip-src-2.2.0

# Pull and build liblas
RUN git clone https://github.com/libLAS/libLAS.git
WORKDIR /data/libLAS
RUN git reset --hard 96d4dc9d6abc93c683ee97cfd14a984148390320
RUN wget https://gitlab.archlinux.org/archlinux/packaging/packages/liblas/-/raw/f49dec6268af6ef8451551f617058b098c8d9b94/fix-gdal-2.5.patch
RUN patch -Np1 -i ./fix-gdal-2.5.patch
RUN cmake -B build \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DWITH_GDAL=ON \
    -DWITH_GEOTIFF=ON \
    -DWITH_LASZIP=ON \
    -DWITH_UTILITIES=ON \
    -DCMAKE_INSTALL_RPATH=/usr/lib/laszip \
    -DLASZIP_INCLUDE_DIR=/usr/include \
    -DLASZIP_LIBRARY=/usr/lib/laszip/liblaszip.so \
    -DGDAL_LIBRARY=/usr/lib/x86_64-linux-gnu/libgdal.so \
    -G "Unix Makefiles"
RUN make -C build
RUN make -C build install
WORKDIR /data
RUN rm -rf libLAS

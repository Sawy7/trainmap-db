#!/bin/sh
sudo docker compose up -d
sudo docker cp ./bootstrap.sh trainmap-db:/data/
sudo docker cp ./stage1.sql trainmap-db:/data/
sudo docker cp ./stage2.sql trainmap-db:/data/
sudo docker cp ./stage3.sql trainmap-db:/data/
sudo docker cp ../raw-data trainmap-db:/data/
sudo docker cp ../import-scripts trainmap-db:/data/

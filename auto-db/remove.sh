#!/bin/sh
sudo docker compose down
sudo rm -rf ./storage
sudo docker image rm trainmap-db

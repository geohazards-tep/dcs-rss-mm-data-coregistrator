#!/bin/sh

sudo conda update conda -y
sudo conda install -y --file /application/dependencies/package.list
sudo pip install rio-toa
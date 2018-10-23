#!/bin/sh

conda update conda -y
conda install -y --file /application/dependencies/package.list
pip install rio-toa
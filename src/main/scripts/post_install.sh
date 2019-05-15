#!/usr/bin/env bash

echo "postinstall script"

export PATH=/opt/anaconda/bin:$PATH
conda update conda -y
conda update python -y
conda install python=3
conda install --file /application/dependencies/packages.list
#pip install rio-toa
rm -rf L8_reflectance
git clone -b develop https://github.com/ESRIN-RSS/L8_reflectance.git
#cd L8_reflectance
pip install -e L8_reflectance

echo "end postinstall script"

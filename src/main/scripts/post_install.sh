#!/usr/bin/env bash
conda update conda -y
conda install --file /application/dependencies/packages.list
export PATH=/opt/anaconda/bin:$PATH
pip install rio-toa
git clone -b develop https://github.com/ESRIN-RSS/L8_reflectance.git
cd L8_reflectance
pip install -e L8_reflectance
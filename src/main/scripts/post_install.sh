#!/usr/bin/env bash
conda update conda -y
conda install --file /application/dependencies/packages.list
export PATH=/opt/anaconda/bin:$PATH
pip install rio-toa

#!/bin/bash

kompsat3="kompsat3|https://catalog.terradue.com//cos2/series/call-677-acquisitions/search?format=json&uid=677-KARI-KOMPSAT3-urn-ogc-def-EOP-KARI-KOMPSAT3-K3_20180614101222_32411_03451327_L1G_Aux_xml"
s2="S2|https://catalog.terradue.com//cos2/series/call-677-acquisitions/search?format=json&uid=S2A_MSIL1C_20181030T081041_N0206_R078_T37TEJ_20181030T083454"
landsat8="L8|https://catalog.terradue.com//cos2/series/call-677-acquisitions/search?format=json&uid=LC08_L1TP_173030_20181031_20181031_01_RT"
s1="S1|https://catalog.terradue.com//cos2/series/call-677-acquisitions/search?format=json&uid=677-ESA-SENTINEL_1B-S1B_IW_GRDH_1SDV_20181029T151825_20181029T151850_013369_018B99_A3BE_SAFE"
pleiades="Pleiades|https://catalog.terradue.com//cos2/series/call-677-acquisitions/search?format=json&uid=677-CNES-PLEIADES_1A-urn-ogc-def-EOP-PHR-1A-DS_PHR1A_201810280821531_FR1_PX_E039N43_0817_00805"

performOpticalCalibration="true"
SubsetBoundingBox="39.604,43.665,39.678,43.695"

# Declare an array of products
declare -a prods=(${kompsat3} ${s2} ${landsat8} ${s1} ${pleiades})

# Declare options for opticalcalibration
declare -a opticalCalibration=("true" "false")
i=0
# Iterate the string array using for loop
for oc in "${opticalCalibration[@]}"; do
  for master in "${prods[@]}"; do
    master_name=${master%|*}
    for slave in "${prods[@]}"; do
      slave_name=${slave%|*}
      master=$(cut -d'|' -f2 <<<"${master}")
      slave=$(cut -d'|' -f2 <<<"${slave}")
      if [[ ! $master = $slave ]]; then
        i=$((i+1))
        job=$(ciop-run -P performOpticalCalibration="${oc}" -P slave="${slave}" -S master="${master}" -P SubsetBoundingBox="${SubsetBoundingBox}" | grep ciop-stop)
        jobl=($job)
        result=($(ciop-run -l | grep "${jobl[6]}"))
        result=${result[2]}
        echo -e "TEST#${i}:\nmaster-${master_name}\nslave-${slave_name}\nperformOpticalCalibration-${oc}\nresult-${result}"
      fi
    done
  done
done



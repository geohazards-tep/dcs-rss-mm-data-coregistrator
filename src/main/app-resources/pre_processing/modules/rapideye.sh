#!/usr/bin/env bash


# RapidEye pre processing function
function pre_processing_rapideye() {
# function call pre_processing_ukdmc2 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"

inputNum=$#
[ "$inputNum" -ne 6 ] && return ${ERR_PREPROCESS}

local prodname=$1
local pixelSpacing=$2
local pixelSpacingMaster=$3
local performCropping=$4
local subsettingBoxWKT=$5
local performOpticalCalibration=$6

prodBasename=$(basename ${prodname})
outProdBasename=$(basename ${prodname})_pre_proc
outProd=${TMPDIR}/${outProdBasename}

# source bands list for Rapideye
sourceBandsList=$(get_band_list "${prodBasename}" "RapidEye" )

imgfile=$(find ${prodname}/ -name '*_RE2_*.tif' | head -1 )

#Optical Calibration (visit: http://wiki.equipex-geosud.fr/index.php/Guide_Administrateur#RapidEye)
if [[ "${performOpticalCalibration}" = true ]]; then
    #get gain and bias values for all bands in dim file
    cd ${prodname}
    gainbiasFile=${TMPDIR}/gainbias.txt
    illuminationsFile=${TMPDIR}/illuminations.txt
    prodMetadataFile=$(find ${prodname}/ -name '*_RE2_*metadata.xml')
    sunElevationAngle=$( cat ${prodMetadataFile} | sed -n 's/.*<opt:illuminationElevationAngle uom="deg">\(.*\)<\/opt:illuminationElevationAngle>.*/\1/p')
    sunElevationAngle=$(printf "%.14f" $sunElevationAngle)
    acquiDate=$( cat ${prodMetadataFile} | sed -n 's/.*<eop:acquisitionDate>\(.*\)<\/eop:acquisitionDate>.*/\1/p')
    acquiDateYear=$( echo $acquiDate | cut -d'-' -f 1)
    acquiDateMonth=$( echo $acquiDate | cut -d'-' -f 2)
    acquiDateDay=$( echo $acquiDate | cut -d'-' -f 3 | cut -d'T' -f 1)
    acquiDateHour=$( echo $acquiDate | cut -d'-' -f 3 | cut -d'T' -f 2 | cut -d':' -f 1 )
    gainchain=''
    biaschain=''
    xIFS=$IFS
    IFS=","
    c=0
    for b in $sourceBandsList ; do
        c=$((c+1))
        gain=$( cat ${prodMetadataFile} | sed -n '/'${c}'/{s/.*<re:radiometricScaleFactor>\(.*\)<\/re:radiometricScaleFactor>.*/\1/p; }')
        gain=$( echo "1/$(printf "%.14f" $gain)" | bc -l)
        gainchain=$gainchain':'$gain
    done
    IFS=$xIFS
    echo ${gainchain#?} > $gainbiasFile
    echo '0:0:0:0:0' >> $gainbiasFile
    echo '1997.8:1863.5:1560.4:1395.0:1124.4' >> $illuminationsFile    #taken from https://www.planet.com/products/satellite-imagery/files/160625-RapidEye%20Image-Product-Specifications.pdf
    #perform the callibration
    outputfile=$( calibrate_optical_TOA ${imgfile} .tif _toa.tif ${gainbiasFile} ${illuminationsFile} "-acqui.sun.elev ${sunElevationAngle} -acqui.year $acquiDateYear -acqui.month $acquiDateMonth -acqui.day $acquiDateDay -acqui.hour $acquiDateHour")
    rm ${imgfile}
    rm $gainbiasFile
    rm $illuminationsFile
    mv ${outputfile} ${imgfile}
    cd -
fi

# set output calibrated filename
outputCal=${imgfile}
outputCalDIM="${outputCal%.tif}.dim"
cd ${prodname}
# convert tif to beam dimap format
ciop-log "INFO" "Invoking SNAP-pconvert on the generated request file for tif to dim conversion"
pconvert -f dim ${outputCal}
# remove intermediate file
rm ${outputCal}
currentBandsList=$( xmlstarlet sel -t -v "/Dimap_Document/Image_Interpretation/Spectral_Band_Info/BAND_NAME" ${outputCalDIM} )
currentBandsList=(${currentBandsList})
currentBandsList_num=${#currentBandsList[@]}
currentBandsListTXT=${TMPDIR}/currentBandsList.txt
# loop on band names to fill band list
let "currentBandsList_num-=1"
for index in `seq 0 $currentBandsList_num`;
do
    if [ $index -eq 0  ] ; then
        echo ${currentBandsList[${index}]} > ${currentBandsListTXT}
    else
        echo  ${currentBandsList[${index}]} >> ${currentBandsListTXT}
    fi
done
# loop over known product bands to fill target bands list
targetBandsNamesListTXT=${TMPDIR}/targetBandsNamesList.txt
# convert band from comma separted values to space separated values
bandListSsv=$( echo "${sourceBandsList}" | sed 's|,| |g' )
# convert ssv to array
declare -a bandListArray=(${bandListSsv})
# get number of bands
numBands=${#bandListArray[@]}
local bid=0
let "numBands-=1"
for bid in `seq 0 $numBands`; do
    if [ $bid -eq 0  ] ; then
        echo ${bandListArray[$bid]} > ${targetBandsNamesListTXT}
    else
        echo ${bandListArray[$bid]} >> ${targetBandsNamesListTXT}
    fi
done
# build request file for rename all the bands contained into the stack product
# report activity in the log
outProdRename=${TMPDIR}/stack_renamed_bands
ciop-log "INFO" "Preparing SNAP request file for bands renaming"
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_rename_all_bands "${outputCalDIM}" "${currentBandsListTXT}" "${targetBandsNamesListTXT}" "${outProdRename}")
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file bands renaming"
# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
# check the exit code
[ $? -eq 0 ] || return $ERR_SNAP
rm -rf ${outProdStack}.d*

# use the greter pixel spacing as target spacing (in order to downsample if needed, upsampling always avoided)
local target_spacing=$( get_greater_pixel_spacing ${pixelSpacing} ${pixelSpacingMaster} )
# check for resampling operator: to be used only if the resolution is differenet from the current product one
local performResample=""
if (( $(bc <<< "$target_spacing != $pixelSpacing") )) ; then
    performResample="true"
else
    performResample="false"
fi
outProdBasename=$(basename ${prodname})_pre_proc
outProd=${TMPDIR}/${outProdBasename}

# report activity in the log
ciop-log "INFO" "Preparing SNAP request file for optical data pre processing"
# source bands list for
sourceBandsList=""
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_rsmpl_rprj_sbs "${outProdRename}.dim" "${performResample}" "${target_spacing}" "${performCropping}" "${subsettingBoxWKT}" "${sourceBandsList}" "${outProd}")
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for optical data pre processing"
# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
# check the exit code
[ $? -eq 0 ] || return $ERR_SNAP

# create a tar archive where DIM output product is stored and put it in OUTPUT dir
cd ${TMPDIR}
tar -cf ${outProdBasename}.tar ${outProdBasename}.d*
mv ${outProdBasename}.tar ${OUTPUTDIR}
rm -rf ${outProdBasename}.d*
rm -rf ${outProdRename}.d*
cd
}
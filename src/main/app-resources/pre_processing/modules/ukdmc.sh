#!/usr/bin/env bash


# UKDMC2 pre processing function
function pre_processing_ukdmc2() {
# function call pre_processing_ukdmc2 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"

inputNum=$#
[ "$inputNum" -ne 6 ] && return ${ERR_PREPROCESS}

local prodname=$1
local pixelSpacing=$2
local pixelSpacingMaster=$3
local performCropping=$4
local subsettingBoxWKT=$5
local performOpticalCalibration=$6

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

# source bands list for UKDMC-2
sourceBandsList="NIR,Red,Green"

#Optical Calibration
if [[ "${performOpticalCalibration}" = true ]]; then
    #get gain and bias values for all bands in dim file
    cd ${prodname}
    gainbiasFile=${TMPDIR}/gainbias.txt
    illuminationsFile=${TMPDIR}/illuminations.txt
    imgfile=$(find ${prodname}/ -name 'U*.tif')
    prodDimFile=$(find ${prodname}/ -name 'U*.dim')
    gainchain=''
    biaschain=''
    IFS=","
    for b in $sourceBandsList ; do
        gain=$( cat ${prodDimFile} | sed -n '/'${b}'/{N; s/.*<PHYSICAL_GAIN>\(.*\)<\/PHYSICAL_GAIN>.*/\1/p; }')
        gainchain=$gainchain':'$gain
        bias=$( cat ${prodDimFile} | sed -n '/'${b}'/{N; N; s/.*<PHYSICAL_BIAS>\(.*\)<\/PHYSICAL_BIAS>.*/\1/p; }')
        biaschain=$biaschain':'$bias
    done
    echo ${gainchain#?} > $gainbiasFile
    echo ${biaschain#?} >> $gainbiasFile
    echo '1036:1561:1811' >> $illuminationsFile
    #perform the callibration
    outputfile=$( calibrate_optical_TOA ${imgfile} .tif _toa.tif ${gainbiasFile} ${illuminationsFile})
    rm ${imgfile}
    rm $gainbiasFile
    rm $illuminationsFile
    mv ${outputfile} ${imgfile}
    cd -
fi

# report activity in the log
ciop-log "INFO" "Preparing SNAP request file for UK-DMC 2 data pre processing"
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_rsmpl_rprj_sbs "${prodname}" "${performResample}" "${target_spacing}" "${performCropping}" "${subsettingBoxWKT}" "${sourceBandsList}" "${outProd}")
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"

# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for UK-DMC 2 data pre processing"

# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
# check the exit code
[ $? -eq 0 ] || return $ERR_SNAP

# create a tar archive where DIM output product is stored and put it in OUTPUT dir
cd ${TMPDIR}
tar -cf ${outProdBasename}.tar ${outProdBasename}.d*
#tar -cjf ${outProdBasename}.tar -C ${TMPDIR} .
mv ${outProdBasename}.tar ${OUTPUTDIR}
rm -rf ${outProdBasename}.d*
cd -
}

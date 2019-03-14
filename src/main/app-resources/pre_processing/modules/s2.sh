#!/usr/bin/env bash

# Sentinel-2 pre processing function
function pre_processing_s2() {
# function call pre_processing_s2 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"

inputNum=$#
[ "$inputNum" -ne 5 ] && return ${ERR_PREPROCESS}

local prodname=$1
local pixelSpacing=$2
local pixelSpacingMaster=$3
local performCropping=$4
local subsettingBoxWKT=$5

unzippedFolder=$(ls $retrievedProduct)
# log the value, it helps debugging.
# the log entry is available in the process stderr
ciop-log "DEBUG" "unzippedFolder: ${unzippedFolder}"
# retrieved product pointing to the unzipped folder
prodname=$retrievedProduct/$unzippedFolder

#get full path of S2 product metadata xml file
# check if it is like S2?_*.xml
# s2_xml=$(ls "${retrievedProduct}"/S2?_*.xml )
s2_xml=$(find ${prodname}/ -name '*.xml' | egrep '^.*/S2[A-Z]?_.*.SAFE/S2[A-Z]?_[A-Z0-9]*.xml$')
# if it not like S2?_*.xml
if [ $? -ne 0 ] ; then
    # check if it is like MTD_*.xml
    #s2_xml=$(ls "${retrievedProduct}"/MTD_*.xml )
    s2_xml=$(find ${prodname}/ -name '*.xml' | egrep '^.*/S2[A-Z]?_.*.SAFE/MTD_[A-Z0-9]*.xml$')
    #if it is neither like MTD_*.xml: return error
    [ $? -ne 0 ] && return $ERR_GETPRODMTD
fi

# use the greter pixel spacing as target spacing (in order to downsample if needed, upsampling always avoided)
local target_spacing=$( get_greater_pixel_spacing ${pixelSpacing} ${pixelSpacingMaster} )

outProdBasename=$(basename ${prodname})_pre_proc
outProd=${TMPDIR}/${outProdBasename}

# report activity in the log
ciop-log "INFO" "Preparing SNAP request file for Sentinel 2 data pre processing"
# source bands list for Sentinel 2
sourceBandsList="B1,B2,B3,B4,B5,B6,B7,B8,B8A,B9,B10,B11,B12"
# resample flag always true because S2 contains bands with differnt sampling steps
performResample="true"
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_rsmpl_rprj_sbs "${s2_xml}" "${performResample}" "${target_spacing}" "${performCropping}" "${subsettingBoxWKT}" "${sourceBandsList}" "${outProd}")
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"

# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for Sentinel 2 data pre processing"

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
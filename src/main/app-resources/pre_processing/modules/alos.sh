#!/usr/bin/env bash


function pre_processing_alos() {
# function call pre_processing_s1 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"

inputNum=$#
[ "$inputNum" -ne 5 ] && return ${ERR_PREPROCESS}

local prodname=$1
local pixelSpacing=$2
local pixelSpacingMaster=$3
local performCropping=$4
local subsettingBoxWKT=$5


## check if ALOS2 product is a folder
#if [[ -d "${retrievedProduct}" ]]; then
#  # check if ALOS2 folder contains a zip file
#  ALOS_ZIP=$(ls ${retrievedProduct} | egrep '^.*ALOS2.*.zip$')
#  cd ${retrievedProduct}
#  # if doesn't contain a zip it should be already uncompressed
#  [[ -z "$ALOS_ZIP" ]] || unzip $ALOS_ZIP
#  test_tif_present=$(ls *.tif)
#  [[ "${test_tif_present}" == "" ]] && (ciop-log "ERROR - empty product folder"; return ${ERR_GETDATA})
#for img in *.tif ; do
#  ciop-log "INFO" "Reprojecting "$mission" image: $img"
#      gdalwarp -ot UInt16 -srcnodata 0 -dstnodata 0 -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -t_srs EPSG:3857 ${img} temp-outputfile.tif
#      returnCode=$?
#      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
#
#  ciop-log "INFO" "Converting to dB "$mission" image: $img"
#  #prepare snap request file for linear to dB conversion
#  SNAP_REQUEST=$( create_snap_request_linear_to_dB "${retrievedProduct}/temp-outputfile.tif" "${retrievedProduct}/temp-outputfile2.tif" )
#  [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
#  [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
#  # invoke the ESA SNAP toolbox
#  gpt ${SNAP_REQUEST} -c "${CACHE_SIZE}" &> /dev/null
#  # check the exit code
#  [ $? -eq 0 ] || return $ERR_SNAP
#done
#  cd -
#fi


unzippedFolder=$(ls $retrievedProduct)
# log the value, it helps debugging.
# the log entry is available in the process stderr
ciop-log "DEBUG" "unzippedFolder: ${unzippedFolder}"
# retrieved product pointing to the unzipped folder
prodname=$retrievedProduct/$unzippedFolder

outProdBasename=$(basename ${prodname})_pre_proc
outProd=${TMPDIR}/${outProdBasename}
ml_factor=$( get_ml_factor "${pixelSpacing}" "${pixelSpacingMaster}" )
# the log entry is available in the process stderr
ciop-log "DEBUG" "ml_factor: ${ml_factor}"

# report activity in the log
ciop-log "INFO" "Preparing SNAP request file for Alos-2 data pre processing"

# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_pre_processing_s1 "${prodname}" "${ml_factor}" "${performCropping}" "${subsettingBoxWKT}" "${outProd}")
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"

# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for Alos-2 data pre processing"

# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "2048M" &> /dev/null
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
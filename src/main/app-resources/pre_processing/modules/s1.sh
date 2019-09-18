#!/usr/bin/env bash

# Sentinel-1 pre processing function
function pre_processing_s1() {
# function call pre_processing_s1 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"

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
#prodname=$retrievedProduct/$unzippedFolder
prodname=$(find ${retrievedProduct} -name "$(basename ${retrievedProduct})")
prodname=$(cut -d' ' -f2 <<<${prodname})

outProdBasename=$(basename ${prodname})_pre_proc
outProd=${TMPDIR}/${outProdBasename}
ml_factor=$( get_ml_factor "${pixelSpacing}" "${pixelSpacingMaster}" )
# the log entry is available in the process stderr
ciop-log "DEBUG" "ml_factor: ${ml_factor}"

# report activity in the log
ciop-log "INFO" "Preparing SNAP request file for Sentinel 1 data pre processing"

# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_pre_processing_s1 "${prodname}" "${ml_factor}" "${performCropping}" "${subsettingBoxWKT}" "${outProd}")
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"

# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for Sentinel 1 data pre processing"

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

function create_snap_request_pre_processing_s1() {

# function call create_snap_request_pre_processing_s1 "${prodname}" "${ml_factor}" "${performCropping}" "${subsettingBoxWKT}"

# function which creates the actual request from
# a template and returns the path to the request

inputNum=$#
[ "$inputNum" -ne 5 ] && return ${ERR_PREPROCESS}

local prodname=$1
local ml_factor=$2
local performCropping=$3
local subsettingBoxWKT=$4
local outprod=$5

local commentSbsBegin=""
local commentSbsEnd=""
local commentMlBegin=""
local commentMlEnd=""
local commentCalSrcBegin=""
local commentCalSrcEnd=""
local commentDbSrcBegin=""
local commentDbSrcEnd=""

local beginCommentXML="<!--"
local endCommentXML="-->"


if [ "${performCropping}" = false ] ; then
    commentSbsBegin="${beginCommentXML}"
    commentSbsEnd="${endCommentXML}"
else
    commentDbSrcBegin="${beginCommentXML}"
    commentDbSrcEnd="${endCommentXML}"
fi

if [ "$ml_factor" -eq 1 ] ; then
    commentMlBegin="${beginCommentXML}"
    commentMlEnd="${endCommentXML}"
else
    commentCalSrcBegin="${beginCommentXML}"
    commentCalSrcEnd="${endCommentXML}"
fi

#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

SNAP_gpt_template="$_CIOP_APPLICATION_PATH/pre_processing/templates/snap_request_s1.xml"

sed -e "s|%%prodname%%|${prodname}|g" \
-e "s|%%commentMlBegin%%|${commentMlBegin}|g" \
-e "s|%%ml_factor%%|${ml_factor}|g" \
-e "s|%%commentMlEnd%%|${commentMlEnd}|g" \
-e "s|%%commentCalSrcBegin%%|${commentCalSrcBegin}|g" \
-e "s|%%commentCalSrcEnd%%|${commentCalSrcEnd}|g" \
-e "s|%%commentSbsBegin%%|${commentSbsBegin}|g" \
-e "s|%%subsettingBoxWKT%%|${subsettingBoxWKT}|g" \
-e "s|%%commentSbsEnd%%|${commentSbsEnd}|g" \
-e "s|%%commentDbSrcBegin%%|${commentDbSrcBegin}|g" \
-e "s|%%outprod%%|${outprod}|g" \
-e "s|%%commentDbSrcEnd%%|${commentDbSrcEnd}|g"  $SNAP_gpt_template > $snap_request_filename


    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}
}

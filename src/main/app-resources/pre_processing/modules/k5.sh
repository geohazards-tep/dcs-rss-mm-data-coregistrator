#!/usr/bin/env bash

# Pre processing function for Kompsat-5
function pre_processing_k5() {
# function call pre_processing_k5 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"

inputNum=$#
[ "$inputNum" -ne 5 ] && return ${ERR_PREPROCESS}

local prodname=$1
local pixelSpacing=$2
local pixelSpacingMaster=$3
local performCropping=$4
local subsettingBoxWKT=$5
local index=0
prodBasename=$(basename ${prodname})
local imgFile=""
imgFile=$(find ${prodname}/ -name 'K5_*_L1D.tif')
# remove metadata from tif to avoid that SNAP-gpt uses the K5 reader (that doesn't work) while converting into DIM
gdal_edit.py -unsetmd ${imgFile}
[ $? -eq 0 ] || return ${ERR_GDAL}
# rename data to avoid that SNAP-gpt uses the K5 reader (that doesn't work) while converting into DIM
file2convert=${TMPDIR}/product2convert.tif
mv ${imgFile} ${file2convert}
# convert tif to beam dimap format
ciop-log "INFO" "Invoking SNAP-pconvert on the generated request file for tif to dim conversion"
pconvert -f dim -o ${TMPDIR} ${file2convert}
# check the exit code
[ $? -eq 0 ] || return $ERR_SNAP
# get translated product name
imgFileDIM=$(find ${TMPDIR} -name '*.dim')
# define output name of DIM product with K5 file converted into dB
imgFileDIM_dB=${TMPDIR}/${prodBasename}_dB.dim
ciop-log "INFO" "Preparing SNAP request file for dB scaling"
SNAP_REQUEST=$( create_snap_request_linear_to_dB "${imgFileDIM}" "${imgFileDIM_dB}" )
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for dB scaling"
# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
# check the exit code
[ $? -eq 0 ] || return $ERR_SNAP
# remove temp file product in beam dimap
rm -rf "${imgFileDIM%.dim}.d*"
# get bands name
currentBandsList=$( xmlstarlet sel -t -v "/Dimap_Document/Image_Interpretation/Spectral_Band_Info/BAND_NAME" ${imgFileDIM_dB} )
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
# source bands list for Pleiades
sourceBandsList=$(get_band_list "${prodBasename}" "Kompsat-5" )
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
# build request file for rename all the bands contained into the product
# report activity in the log
outProdRename=${TMPDIR}/output_renamed_bands
ciop-log "INFO" "Preparing SNAP request file for bands renaming"
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_rename_all_bands "${imgFileDIM_dB}" "${currentBandsListTXT}" "${targetBandsNamesListTXT}" "${outProdRename}")
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
# remove temp calibrated file product in beam dimap
rm -rf "${imgFileDIM_dB%.dim}.d*"

# use the greter pixel spacing as target spacing (in order to downsample if needed, upsampling always avoided)
local target_spacing=$( get_greater_pixel_spacing ${pixelSpacing} ${pixelSpacingMaster} )
# check for resampling operator: to be used only if the resolution is differenet from the current product one
local performResample=""
if (( $(bc <<< "$target_spacing != $pixelSpacing") )) ; then
    performResample="true"
else
    performResample="false"
fi
outProdBasename=${prodBasename}_pre_proc
outProd=${TMPDIR}/${outProdBasename}

# report activity in the log
ciop-log "INFO" "Preparing SNAP request file for data pre processing"
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_rsmpl_rprj_sbs "${outProdRename}.dim" "${performResample}" "${target_spacing}" "${performCropping}" "${subsettingBoxWKT}" "${sourceBandsList}" "${outProd}")
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
[ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for data pre processing"
# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "${CACHE_SIZE}" 2> log.txt
returncode=$?
test_txt=$(cat log.txt | grep "No intersection")
#rm -rf ${outProdRename}.d* ${targetBandsNamesListTXT}
# create a tar archive where DIM output product is stored and put it in OUTPUT dir
cd ${TMPDIR}
tar -cf ${outProdBasename}.tar ${outProdBasename}.d*
#tar -cjf ${outProdBasename}.tar -C ${TMPDIR} .
mv ${outProdBasename}.tar ${OUTPUTDIR}
rm -rf ${outProdBasename}.d*
cd -
}
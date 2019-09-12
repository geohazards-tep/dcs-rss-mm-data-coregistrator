#!/usr/bin/env bash

# generic optical mission (not fully supported by SNAP) pre processing function
function pre_processing_spot_pleiades() {

# function call pre_processing_generic_optical "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"

inputNum=$#
[ "$inputNum" -ne 7 ] && return ${ERR_PREPROCESS}

local prodname=$1
local mission=$2
local pixelSpacing=$3
local pixelSpacingMaster=$4
local performCropping=$5
local subsettingBoxWKT=$6
local performOpticalCalibration=$7
prodBasename=$(basename ${prodname})

local index=0
if [[ -d "${prodname}" ]]; then
  jp2_product=""
  # Get multispectral image file
  if [ ${mission} = "PLEIADES" ]; then
      jp2_product=$(find ${prodname}/ -name 'IMG_*MS_*.JP2')
  else
      # SPOT case
      jp2_product=$(find ${prodname}/ -name 'IMG_SPOT?_*MS_*.JP2')
  fi
  # convert ssv to array
  declare -a jp2_product_arr=(${jp2_product})
  # get number of bands
  local numProd=${#jp2_product_arr[@]}
  [ $numProd -eq 0  ] && return ${ERR_CONVERT}
  local prodId=0
  let "numProd-=1"
  cd $( dirname ${jp2_product})
  for prodId in `seq 0 $numProd`; do
    currentProd=${jp2_product_arr[$prodId]}
    if [[ "${performOpticalCalibration}" = true ]]; then
        outputfile=$( calibrate_optical_TOA ${currentProd} .JP2 .tif)
    else
        outputfile="${currentProd%.JP2}.tif"
        gdal_translate ${currentProd} ${outputfile} -of GTiff
    fi
    ciop-log "DEBUG" "Output file is ${outputfile}"
  done
  imgFiles=$(find $( pwd )/ -name 'IMG_*MS*_R?C?.tif')
  outputCal=${outputfile}
  #If tiles exist merge all tiles
  tilesNum=$( get_num_tiles ${prodname} )
  if [ ${tilesNum} -gt 1 ]; then
      ciop-log "INFO" "The image is divided into ${tilesNum} tiles"
      imgFile1=(${imgFiles})
      untiledVrtFile="${imgFile1%_R?C?.tif}.vrt"
      ciop-log "INFO" "Performing image fusion to ${untiledVrtFile}"
      gdalbuildvrt ${untiledVrtFile} ${imgFiles}
      outimgFile="${untiledVrtFile%.vrt}.tif"
      gdal_translate ${untiledVrtFile} ${outimgFile} -of GTiff
      outputCal=${outimgFile}
  fi
fi


# set output calibrated filename
outputCalDIM="${outputCal%.tif}.dim"
ciop-log "DEBUG" "The dim file is ${outputCalDIM}"
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
# source bands list for Pleiades
sourceBandsList=$(get_band_list "${prodBasename}" "${mission}" )
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
    # Temporary solution: Limit the pixel size to 1m in order to prevent memory issues.
    if (( $(bc <<< "$pixelSpacing < 1") )) ; then
        local pixelSpacing="1 m"
        local target_spacing=$( get_greater_pixel_spacing ${pixelSpacing} ${pixelSpacingMaster} )
    fi
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
#tar -cjf ${outProdBasename}.tar -C ${TMPDIR} .
mv ${outProdBasename}.tar ${OUTPUTDIR}
rm -rf ${outProdBasename}.d*
rm -rf ${outProdRename}.d*
cd
}

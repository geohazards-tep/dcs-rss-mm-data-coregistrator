#!/usr/bin/env bash

# generic optical mission (not fully supported by SNAP) pre processing function
function pre_processing_generic_optical() {

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

# loop to fill contained TIFs and their basenames
local tifList=${TMPDIR}/tifList.txt
local filesListCSV=""
targetBandsNamesListTXT=${TMPDIR}/targetBandsNamesList.txt
local index=0

# mission dependent TIF list
# if Landsat-8 it can be compressed in tar.bz
if [ ${mission} = "Landsat-8" ]; then
    ext=".TIF"
    #Check if downloaded product is compressed and extract it
    ext="${prodname##*/}"; ext="${ext#*.}"
    ciop-log "INFO" "Product extension is: $ext"
    if [ "$ext" == "tar.bz" ] || [ "$ext" == "tar" ]; then
        ciop-log "INFO" "Extracting $prodname"
        currentBasename=$(basename $prodname)
        currentBasename="${currentBasename%%.*}"
        mkdir -p ${prodname%/*}/${currentBasename}
        cd ${prodname%/*}
        filename="${prodname##*/}"
        tar xf $filename -C ${currentBasename}
        returnCode=$?
        ext=".TIF"
        [ $returnCode -eq 0 ] || return ${ERR_UNPACKING}
        prodname=${prodname%/*}/${currentBasename}
        ls "${prodname}"/LC*_B[1-7]${ext} > $tifList
        ls "${prodname}"/LC*_B9${ext} >> $tifList
        ls "${prodname}"/LC*_B1[0,1]${ext} >> $tifList
    else
        ls "${prodname}"/LS08*_B[0-1][0-7,9]${ext} > $tifList
    fi
    cd -
    if [[ "${performOpticalCalibration}" = true ]]; then
        ciop-log "INFO" "Performing Optical Calibration for Landsat8..."
        L8_reflectance ${prodname} $( dirname ${prodname})
        metadatafile=$(ls ${prodname}/*_MTL.txt)
        mv $metadatafile ${metadatafile//${prodname}/${prodname}_TOA}
        b9=$(ls "${prodname}"/LC*_B9${ext})
        mv "${b9}" ${b9//${prodname}/${prodname}_TOA}
        rm -rf ${prodname}
        mv ${prodname}_TOA ${prodname}
        for toa in $(ls "${prodname}"); do
            mv "${prodname}/$toa" "${prodname}/${toa//_TOA/}"
        done
        ls "${prodname}"/LC*_B[1-7]${ext} > $tifList
#        ls "${prodname}"/LC*_B9${ext} >> $tifList
        ls "${prodname}"/LC*_B1[0,1]${ext} >> $tifList
    fi
elif [ ${mission} = "Kompsat-2" ]; then
    ext=".tif"
    ls "${prodname}"/*/MSC_*[R,G,B,N]_1G${ext} > $tifList
    #Optical Calibration
    if [[ "${performOpticalCalibration}" = true ]]; then
        #get gain and bias values for all bands in dim file
        cd ${prodname}/MSC*
        k2gains='8.01976069034:8.5047754314:7.40729766966:6.34666768213'
        k2bias='0.0 : 0.0 : 0.0 : 0.0'
        k2illuminations='1838:1915:1075:1534'
        #perform the callibration for each band
        n=0
        for tif in $(cat "${tifList}"); do
            gainbiasFile=${TMPDIR}/gainbias.txt
            illuminationsFile=${TMPDIR}/illuminations.txt
            n=$(($n+1))
            echo $k2gains | cut -d':' -f$n > $gainbiasFile
            echo $k2bias | cut -d':' -f$n >> $gainbiasFile
            echo $k2illuminations | cut -d':' -f$n > $illuminationsFile
            outputfile=$( calibrate_optical_TOA ${tif} .tif _toa.tif ${gainbiasFile} ${illuminationsFile})
            rm $gainbiasFile
            rm $illuminationsFile
            rm ${tif}
            mv ${outputfile} ${tif}
        done
        cd -
    fi
elif [ ${mission} = "Kompsat-3" ]; then
    ext=".tif"
    ls "${prodname}"/*/K3_*_L1G_[R,G,B,N]*${ext} > $tifList
    #Optical Calibration
    if [[ "${performOpticalCalibration}" = true ]]; then
        #get gain and bias values for all bands in dim file
        cd ${prodname}/K3*
        k3gains='55.2181115406:39.3545848091:76.9230769231:49.4315373208'
        k3bias='0.0 : 0.0 : 0.0 : 0.0'
        k3illuminations='2001:1875:1027:1525'
        #perform the callibration for each band
        n=0
        for tif in $(cat "${tifList}"); do
            gainbiasFile=${TMPDIR}/gainbias.txt
            illuminationsFile=${TMPDIR}/illuminations.txt
            n=$(($n+1))
            echo $k3gains | cut -d':' -f$n > $gainbiasFile
            echo $k3bias | cut -d':' -f$n >> $gainbiasFile
            echo $k3illuminations | cut -d':' -f$n > $illuminationsFile
            outputfile=$( calibrate_optical_TOA ${tif} .tif _toa.tif ${gainbiasFile} ${illuminationsFile})
            rm $gainbiasFile
            rm $illuminationsFile
            rm ${tif}
            mv ${outputfile} ${tif}
        done
        cd -
    fi
elif [ ${mission} = "VRSS1" ]; then
    #Check if downloaded product is compressed and extract it (in tar is not automatically extracted, otherwise yes)
    ext="${prodname##*/}"; ext="${ext#*.}"
    ciop-log "INFO" "Product extension is: $ext"
    # assumption is that the product has .tar extension or is already uncompressed
    if  [[ "$ext" == "tar" ]]; then
        ciop-log "INFO" "Extracting $prodname"
        currentBasename=$(basename $prodname)
        currentBasename="${currentBasename%%.*}"
        mkdir -p ${prodname%/*}/${currentBasename}
        cd ${prodname%/*}
        filename="${prodname##*/}"
        tar xf $filename -C ${currentBasename}
        returnCode=$?
        [ $returnCode -eq 0 ] || return ${ERR_UNPACKING}
        prodname=${prodname%/*}/${currentBasename}
    fi
    prodBasename=$(basename ${prodname})
    vrss1_b1=$(find ${prodname}/ -name '*_1.tif')
    vrss1_name="${vrss1_b1%_1.tif}"
    vrss1_name=$(basename ${vrss1_name})
    # in this case the product name is not common
    # to the base band names ---> rename all bands
#    if [ ${prodBasename} != ${vrss1_name} ]; then
#        # in this case the product name is not common
#        # to the base band names ---> rename all bands
#        echo we re inside
#        for bix in 1 2 3 4 ;
#        do
#           currentTif=$(ls "${prodname}"/*_"${bix}".tif)
#           echo $currentTif
#           mv ${currentTif} ${prodname}/${prodBasename}_${bix}.tif
#           [[ $bix == "1"  ]] && ls ${prodname}/${prodBasename}_${bix}.tif > $tifList || ls ${prodname}/${prodBasename}_${bix}.tif >> $tifList
#        done
#    else
        ls "${prodname}"/VRSS*_1.tif > $tifList
        ls "${prodname}"/VRSS*_2.tif >> $tifList
        ls "${prodname}"/VRSS*_3.tif >> $tifList
        ls "${prodname}"/VRSS*_4.tif >> $tifList
#    fi

    if [[ "${performOpticalCalibration}" = true ]]; then
        # source bands list for Rapideye
        sourceBandsList=$(get_band_list "${prodBasename}" "VRSS1" )
        #get gain and bias values for all bands in dim file
        cd ${prodname}
        prodMetadataFile=$(find ${retrievedProduct}/ -name 'VRSS*_L2B_*[0-9].xml')
        illuminations=$( cat ${prodMetadataFile} | sed -n '{s/.*<SolarIrradiance.*>\(.*\)<\/SolarIrradiance>.*/\1/p; }')
        bias=$( cat ${prodMetadataFile} | sed -n '{s/.*<K>\(.*\)<\/K>/\1/p; }')
        gains=$( cat ${prodMetadataFile} | sed -n '{s/.*<B>\(.*\)<\/B>/\1/p; }')
        illuminations=$( echo ${illuminations} | sed 's/ /:/g')
        bias=$( echo ${bias} | sed 's/ /:/g')
        gains=$( echo ${gains} | sed 's/ /:/g')
        #perform the callibration for each band
        n=0
        for tif in $(cat "${tifList}"); do
            gainbiasFile=${TMPDIR}/gainbias.txt
            illuminationsFile=${TMPDIR}/illuminations.txt
            n=$(($n+1))
            echo $gains | cut -d':' -f$n > $gainbiasFile
            echo $bias| cut -d':' -f$n >> $gainbiasFile
            echo ${illuminations#?} | cut -d':' -f$n > $illuminationsFile
            outputfile=$( calibrate_optical_TOA ${tif} .tif _toa.tif ${gainbiasFile} ${illuminationsFile})
            rm $gainbiasFile
            rm $illuminationsFile
            rm ${tif}
            mv ${outputfile} ${tif}
        done
        cd -
    fi
elif [[ "${mission}" == "GF2" ]]; then
    filename="${retrievedProduct##*/}"; ext="${filename#*.}"
    # check extension, uncrompress and get product name
    if [[ "$ext" == "tar" ]]; then
      ciop-log "INFO" "Extracting $retrievedProduct"
      currentBasename=$(basename $retrievedProduct)
      currentBasename="${currentBasename%%.*}"
      mkdir -p ${retrievedProduct%/*}/${currentBasename}
      cd ${retrievedProduct%/*}
      tar xf $filename -C ${currentBasename}
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_UNPACKING}
      prodname=${retrievedProduct%/*}/${currentBasename}
      prodBasename=$(basename ${prodname})
      # get multispectral tif product
      mss_product=$(ls "${prodname}"/*MSS2.tiff)
    else
      return ${ERR_GETDATA}
    fi
    #define output filename
    outputfile=${prodBasename}.tif
else
    return ${ERR_PREPROCESS}
fi

for tif in $(cat "${tifList}"); do
    #unpack geotiff if needed
    unpack_geotiff $tif
    basenameNoExt=$(basename "$tif")
    basenameNoExt="${basenameNoExt%.*}"
    if [ $index -eq 0  ] ; then
        filesListCSV=$tif
        echo ${basenameNoExt} > ${targetBandsNamesListTXT}
    else
        filesListCSV=$filesListCSV,$tif
        echo ${basenameNoExt} >> ${targetBandsNamesListTXT}
    fi
    let "index=index+1"
done
# number of product equal to the last index value due to how the loop works
numProd=$index
# report activity in the log
ciop-log "INFO" "Preparing SNAP request file for products stacking"
# output prodcut name
outProdStack=${TMPDIR}/stack_product
# customized processing for kompsat-2 and VRSS1 because snap fails
if [ ${mission} = "VRSS1" ] ; then
    # convert file list from comma separted values to space separated values
    filesListSsv=$( echo "${filesListCSV}" | sed 's|,| |g' )
    # convert ssv to array
    declare -a filesListArray=(${filesListSsv})
    # gdal_merge to create stack product
    gdal_merge.py -separate -n 0 "${filesListArray[0]}" "${filesListArray[1]}" "${filesListArray[2]}" "${filesListArray[3]}"  -o ${outProdStack}.tif
    [ $? -eq 0 ] || return ${ERR_GDAL}
    # pconvert to convert GeoTIFF to BEAM-DIMAP
    pconvert -f dim -o ${TMPDIR} ${outProdStack}.tif
    [ $? -eq 0 ] || return ${ERR_PCONVERT}
    # remove intermediate GeoTIFF K2 stack
    rm ${outProdStack}.tif
else
    # prepare the SNAP request
    SNAP_REQUEST=$( create_snap_request_stack "${filesListCSV}" "${outProdStack}" "${numProd}" )
    [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
    [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
    # report activity in the log
    ciop-log "INFO" "Invoking SNAP-gpt request file for products stacking"
    # invoke the ESA SNAP toolbox
    gpt $SNAP_REQUEST -c "${CACHE_SIZE}"    &> /dev/null
    # check the exit code
    [ $? -eq 0 ] || return $ERR_SNAP
fi
# get band names
outputCalDIM=${outProdStack}.dim
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
#tar -cjf ${outProdBasename}.tar -C ${TMPDIR} .
mv ${outProdBasename}.tar ${OUTPUTDIR}
rm -rf ${outProdBasename}.d*
rm -rf ${outProdRename}.d*
cd

}
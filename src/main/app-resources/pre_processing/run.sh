#!/bin/bash

# source the ciop functions (e.g. ciop-log, ciop-getparam)
source ${ciop_job_include}

# set the environment variables to use ORFEO toolbox
source $_CIOP_APPLICATION_PATH/otb/otb_include.sh

# set the environment variables to use ESA SNAP toolbox
#export SNAP_HOME=$_CIOP_APPLICATION_PATH/common/snap
#export PATH=${SNAP_HOME}/bin:${PATH}
source $_CIOP_APPLICATION_PATH/gpt/snap_include.sh

## put /opt/anaconda/bin ahead to the PATH list to ensure gdal to point to the anaconda installation dir
export PATH=/opt/anaconda/bin:${PATH}

# define the exit codes
SUCCESS=0
SNAP_REQUEST_ERROR=1
ERR_SNAP=2
ERR_NOPROD=3
ERR_NORETRIEVEDPROD=4
ERR_GETMISSION=5
ERR_GETDATA=6
ERR_WRONGINPUTNUM=7
ERR_GETPRODTYPE=8
ERR_WRONGPRODTYPE=9
ERR_GETPRODMTD=10
ERR_PCONVERT=11
ERR_GETPIXELSPACING=12
ERR_CALLPREPROCESS=13
ERR_PREPROCESS=14
ERR_UNPACKING=15
ERR_BAND_LIST=16
ERR_AOI=17
ERR_GDAL=18
ERR_OTB=19
ERR_CONVERT=20


# add a trap to exit gracefully
function cleanExit ()
{
    local retval=$?
    local msg=""

    case ${retval} in
        ${SUCCESS})               msg="Processing successfully concluded";;
        ${SNAP_REQUEST_ERROR})    msg="Could not create snap request file";;
        ${ERR_SNAP})              msg="SNAP failed to process";;
        ${ERR_NOPROD})            msg="No product reference input provided";;
        ${ERR_NORETRIEVEDPROD})   msg="Product not correctly downloaded";;
        ${ERR_GETMISSION})        msg="Error while retrieving mission name from product name or mission data not supported";;
        ${ERR_GETDATA})           msg="Error while discovering product";;
        ${ERR_WRONGINPUTNUM})     msg="Number of input products less than 1";;
        ${ERR_GETPRODTYPE})       msg="Error while retrieving product type info from input product name";;
        ${ERR_WRONGPRODTYPE})     msg="Product type not supported";;
        ${ERR_GETPRODMTD})        msg="Error while retrieving metadata file from product";;
        ${ERR_PCONVERT})          msg="PCONVERT failed to process";;
        ${ERR_GETPIXELSPACING})   msg="Error while retrieving pixel spacing";;
        ${ERR_CALLPREPROCESS})    msg="Error while calling pre processing function";;
        ${ERR_PREPROCESS})        msg="Error during pre processing execution";;
	    ${ERR_UNPACKING})         msg="Error unpacking input product";;
	    ${ERR_BAND_LIST})   	  msg="Error while retrieving the list of contained bands within product";;
	    ${ERR_AOI})               msg="Error: input SubsetBoundingBox has no intersection with input data";;
	    ${ERR_GDAL})              msg="Gdal_translate failed to process";;
	    ${ERR_OTB})          	  msg="Orfeo Toolbox failed to process";;
	    ${ERR_CONVERT})           msg="Convert failed to process";;
        *)                        msg="Unknown error";;
    esac

   [ ${retval} -ne 0 ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
   exit ${retval}
}

trap cleanExit EXIT


# function that checks the product type from the product name
function check_product_type() {

  local retrievedProduct=$1
  local mission=$2
  local productName=$( basename "$retrievedProduct")

  if [ ${mission} = "Sentinel-1"  ] ; then
      #productName assumed like S1A_IW_TTTT_* where TTTT is the product type to be extracted
      prodTypeName=$( echo ${productName:7:4} )
      [ -z "${prodTypeName}" ] && return ${ERR_GETPRODTYPE}
      if [ $prodTypeName != "GRDH" ] && [ $prodTypeName != "GRDM" ]; then
          return $ERR_WRONGPRODTYPE
      fi
  fi

  if [ ${mission} = "Sentinel-2"  ] ; then
      # productName assumed like S2A_TTTTTT_* where TTTTTT is the product type to be extracted
      prodTypeName=$( echo ${productName:4:6} )
      [ -z "${prodTypeName}" ] && return ${ERR_GETPRODTYPE}
      [ $prodTypeName != "MSIL1C" ] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "UK-DMC2" ]]; then
      prodTypeName=$(ls ${retrievedProduct} | sed -n -e 's|^.*_\(.*\)\.tif$|\1|p')
      [[ -z "$prodTypeName" ]] && return ${ERR_GETPRODTYPE}
      [[ "$prodTypeName" != "L1T" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "Kompsat-2" ]; then
      prodTypeName=$(ls ${retrievedProduct}/*/*.tif | head -1 | sed -n -e 's|^.*_\(.*\).tif$|\1|p')
      [[ -z "$prodTypeName" ]] && return ${ERR_GETPRODTYPE}
      [[ "$prodTypeName" != "1G" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "Kompsat-3"  ]; then
      prodTypeName=$(ls ${retrievedProduct}/*/*.tif | head -1 | sed -n -e 's|^.*_\(.*\)_[A-Z].tif$|\1|p')
      [[ -z "$prodTypeName" ]] && return ${ERR_GETPRODTYPE}
      [[ "$prodTypeName" != "L1G" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "Kompsat-5"  ]; then
      prodTypeName=$(ls ${retrievedProduct}/*L??.tif | head -1 | sed -n -e 's|^.*_\(.*\).tif$|\1|p')
      [[ -z "$prodTypeName" ]] && return ${ERR_GETPRODTYPE}
      [[ "$prodTypeName" != "L1D" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "RapidEye"  ]; then
      prodTypeName=$(ls ${retrievedProduct}/*.tif | head -1 | sed -n -e 's/.*\([0-9][A-Z]*\)-.*/\1/p')
      [[ -z "$prodTypeName" ]] && return ${ERR_GETPRODTYPE}
      [[ "$prodTypeName" != "3A" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "Landsat-8" ]; then
      prodTypeName=""
      #Extract metadata file from Landsat
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      if [[ "$ext" == "tar.bz" || "$ext" == "tar" ]]; then
          #tar xf $retrievedProduct ${filename%%.*}_MTL.txt
          mtdfile="$( tar xf $retrievedProduct -v --wildcards "*_MTL.txt")"
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          [[ -e "${mtdfile}" ]] || return ${ERR_GETPRODTYPE}
          prodTypeName=$(sed -n -e 's|^.*DATA_TYPE.*\"\(.*\)\".*$|\1|p' ${mtdfile})
          rm -f ${mtdfile}
          #[ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          #[[ -e "${filename%%.*}_MTL.txt" ]] || return ${ERR_GETPRODTYPE}
          #prodTypeName=$(sed -n -e 's|^.*DATA_TYPE.*\"\(.*\)\".*$|\1|p' ${filename%%.*}_MTL.txt)
          #rm -f ${filename%%.*}_MTL.txt
      else
          metadatafile=$(ls ${retrievedProduct}/*_MTL.txt)
          [[ -e "${metadatafile}" ]] || return ${ERR_GETPRODTYPE}
          prodTypeName=$(sed -n -e 's|^.*DATA_TYPE.*\"\(.*\)\".*$|\1|p' ${metadatafile})
          ciop-log "INFO" "prodtype: ${prodTypeName}"
      fi
      if [[ "$prodTypeName" != "L1TP" ]] && [[ "$prodTypeName" != "L1T" ]]; then
          return $ERR_WRONGPRODTYPE
      fi
  fi
  if [[ "${mission}" == "SPOT-6" ]] || [[ "${mission}" == "SPOT-7"  ]] || [[ "${mission}" == "PLEIADES"  ]]; then
        spot_xml=$(find ${retrievedProduct}/ -name 'DIM_*MS_*.XML')
        prodTypeName=$(sed -n -e 's|^.*<DATASET_TYPE>\(.*\)</DATASET_TYPE>$|\1|p' ${spot_xml})
        [[ "$prodTypeName" != "RASTER_ORTHO" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "VRSS1" ]]; then
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      # assumption is that the product has .tar extension or is already uncompressed
      if  [[ "$ext" == "tar" ]]; then
      # if tar uncompress the product
          ciop-log "INFO" "Running command: tar xf $retrievedProduct"
          tar xf $retrievedProduct
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          # find the fisrt band tif product
          vrss1_b1=$(find ./ -name '*_1.tif')
          [[ "${vrss1_b1}" == "" ]] && return ${ERR_GETPRODTYPE}
          dir_untar_vrss1=$(dirname ${vrss1_b1})
          rm -r -f ${dir_untar_vrss1}
      else
          vrss1_b1=$(find ${retrievedProduct}/ -name '*_1.tif')
          [[ "${vrss1_b1}" == "" ]] && return ${ERR_GETPRODTYPE}
      fi
      # extract product type from product name
      vrss1_b1=$(basename ${vrss1_b1})
      l2b_test=$(echo "${vrss1_b1}" | grep "L2B")
      [[ "${l2b_test}" != "" ]] && prodTypeName="L2B" ||  return $ERR_WRONGPRODTYPE
  fi

  echo ${prodTypeName}
  return 0
}


# function that download and unzip data using the data catalougue reference
function get_data() {

  local ref=$1
  local target=$2
  local local_file
  local enclosure
  local res

  #get product url from input catalogue reference
  enclosure="$( opensearch-client -f atom "${ref}" enclosure)"
  # opensearh client doesn't deal with local paths
  res=$?
  [ $res -eq 0 ] && [ -z "${enclosure}" ] && return ${ERR_GETDATA}
  [ $res -ne 0 ] && enclosure=${ref}

  enclosure=$(echo "${enclosure}" | tail -1)

  #download data and get data name
  local_file="$( echo ${enclosure} | ciop-copy -f -O ${target} - 2> ${TMPDIR}/ciop_copy.stderr )"
  res=$?

  [ ${res} -ne 0 ] && return ${res}
  echo ${local_file}
}


# function that retrieves the mission data identifier from the product name
function mission_prod_retrieval(){
        local mission=""
        prod_basename=$1

        prod_basename_substr_3=${prod_basename:0:3}
        prod_basename_substr_4=${prod_basename:0:4}
        prod_basename_substr_5=${prod_basename:0:5}
        [ "${prod_basename_substr_3}" = "S1A" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S1B" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S2A" ] && mission="Sentinel-2"
        [ "${prod_basename_substr_3}" = "S2B" ] && mission="Sentinel-2"
#        [ "${prod_basename_substr_3}" = "K5_" ] && mission="Kompsat-5"
        [ "${prod_basename_substr_3}" = "K3_" ] && mission="Kompsat-3"
        [ "${prod_basename_substr_3}" = "LC8" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "LS08" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "MSC_" ] && mission="Kompsat-2"
        [ "${prod_basename_substr_4}" = "FCGC" ] && mission="PLEIADES"
        [ "${prod_basename_substr_5}" = "U2007" ] && mission="UK-DMC2"
        [ "${prod_basename_substr_5}" = "ORTHO" ] && mission="UK-DMC2"
        [ "${prod_basename}" = "Resurs-P" ] && mission="Resurs-P"
        [ "${prod_basename}" = "Kanopus-V" ] && mission="Kanopus-V"
        alos2_test=$(echo "${prod_basename}" | grep "ALOS2")
        [ "${alos2_test}" = "" ] || mission="Alos-2"
        spot6_test=$(echo "${prod_basename}" | grep "SPOT6")
        [[ -z "${spot6_test}" ]] && spot6_test=$(ls "${retrievedProduct}" | grep "SPOT6")
        [ "${spot6_test}" = "" ] || mission="SPOT-6"
        spot7_test=$(echo "${prod_basename}" | grep "SPOT7")
        [[ -z "${spot7_test}" ]] && spot7_test=$(ls "${retrievedProduct}" | grep "SPOT7")
        [ "${spot7_test}" = "" ] || mission="SPOT-7"
        pleiades_test=$(echo "${prod_basename}" | grep "PHR")
        [[ -z "${pleiades_test}" ]] && pleiades_test=$(ls "${retrievedProduct}" | grep "PHR")
        [ "${pleiades_test}" = "" ] || mission="PLEIADES"
        [[ -z "${rapideye_test}" ]] && rapideye_test=$(ls "${retrievedProduct}" | grep "RE2")
        [ "${rapideye_test}" = "" ] || mission="RapidEye"
#        vrss1_test_1=$(echo "${prod_basename}" | grep "VRSS1")
#        vrss1_test_2=$(echo "${prod_basename}" | grep "VRSS-1")
#        if [[ "${vrss1_test_1}" != "" ]] || [[ "${vrss1_test_2}" != "" ]]; then
#            mission="VRSS1"
#        fi
        if [ "${mission}" != "" ] ; then
            echo ${mission}
        else
            return ${ERR_GETMISSION}
        fi
}


# function that runs the gets the pixel size in meters depending on the mission data
function get_pixel_spacing() {

# function call get_pixel_size "${mission}"
local mission=$1
local prodname=$2
local prodType=$3

case "$mission" in
        "Sentinel-1")
            acqMode=$(get_s1_acq_mode "${prodname}")
            if [ "${acqMode}" == "EW" ]; then
                if [ "${prodType}" == "GRDH" ]; then
                echo 25
            elif [ "${prodType}" == "GRDM" ]; then
                echo 40
            else
                return ${ERR_GETPIXELSPACING}
            fi
                elif [ "${acqMode}" == "IW" ]; then
            if [ "${prodType}" == "GRDH" ]; then
                echo 10
                    elif [ "${prodType}" == "GRDM" ]; then
                echo 40
                    else
                        return ${ERR_GETPIXELSPACING}
                    fi
                else
            return ${ERR_GETPIXELSPACING}
            fi
            ;;

        "Sentinel-2")
            echo 10
            ;;

        "UK-DMC2")
            echo 22
            ;;

        "Kompsat-2")
            echo 4
            ;;

        "Kompsat-3")
            echo 2.8
            ;;

        "Kompsat-5")
            product_xml=$(find ${retrievedProduct}/ -name 'K5_*_Aux.xml')
            pixSpac=$( cat ${product_xml} | grep GroundRangeGeometricResolution | sed -n -e 's|^.*<GroundRangeGeometricResolution>\(.*\)</GroundRangeGeometricResolution>|\1|p' )
            echo  $pixSpac | awk '{ print sprintf("%.9f", $1); }'
            ;;

        "Landsat-8")
            echo 30
            ;;

	    "SPOT-6")
            spot_xml=$(find ${retrievedProduct}/ -name 'DIM_SPOT?*MS_*.XML' )
            pixSpac=$( cat ${spot_xml} | grep RESAMPLING_SPACING | sed -n -e 's|^.*<RESAMPLING_SPACING .*>\(.*\)</RESAMPLING_SPACING>|\1|p' )
            echo  $pixSpac | awk '{ print sprintf("%.9f", $1); }'
            ;;

        "SPOT-7")
            spot_xml=$(find ${retrievedProduct}/ -name 'DIM_SPOT?*MS_*.XML' )
            pixSpac=$( cat ${spot_xml} | grep RESAMPLING_SPACING | sed -n -e 's|^.*<RESAMPLING_SPACING .*>\(.*\)</RESAMPLING_SPACING>|\1|p' )
            echo  $pixSpac | awk '{ print sprintf("%.9f", $1); }'
            ;;

        "PLEIADES")
            spot_xml=$(find ${retrievedProduct}/ -name 'DIM_*MS_*.XML' )
            pixSpac=$( cat ${spot_xml} | grep RESAMPLING_SPACING | sed -n -e 's|^.*<RESAMPLING_SPACING .*>\(.*\)</RESAMPLING_SPACING>|\1|p' )
            echo  $pixSpac | awk '{ print sprintf("%.9f", $1); }'
            ;;

        "RapidEye")
            rapideye_xml=$(find ${retrievedProduct}/ -name '*_RE2_*_metadata.xml' )
            pixSpac=$( cat ${rapideye_xml} | grep resolution | sed -n -e 's|^.*<eop:resolution uom="m">\(.*\)</eop:resolution>.*|\1|p' )
            echo  $pixSpac | awk '{ print sprintf("%.9f", $1); }'
            ;;

        "VRSS1")
            product_xml=$(find ${retrievedProduct}/ -name 'VRSS*_L2B_*[0-9].xml')
            pixSpac=$( cat ${product_xml} | grep pixelSpacing | sed -n -e 's|^.*<pixelSpacing>\(.*\)</pixelSpacing>|\1|p' )
            echo  $pixSpac | awk '{ print sprintf("%.9f", $1); }'
            ;;

        *)
            return ${ERR_GETPIXELSPACING}
	    ;;
esac

return 0

}


# function that gets the Sentinel-1 acquisition mode from product name
function get_s1_acq_mode(){
# function call get_s1_acq_mode "${prodname}"
local prodname=$1
# filename convention assumed like S1A_AA_* where AA is the acquisition mode to be extracted
acqMode=$( echo ${prodname:4:2} )
echo ${acqMode}
return 0
}


# function that runs the pre processing depending on the mission data
function pre_processing() {

# function call pre_processing "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"
inputNum=$#
[ "$inputNum" -ne 7 ] && return ${ERR_CALLPREPROCESS}

local prodname=$1
local mission=$2
local pixelSpacing=$3
local pixelSpacingMaster=$4
local performCropping=$5
local subsettingBoxWKT=$6
local performOpticalCalibration=$7

case "$mission" in
        "Sentinel-1")
	    pre_processing_s1 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"
            return $?
	    ;;

        "Sentinel-2")
	    pre_processing_s2 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"
            return $?
	    ;;

        "UK-DMC2")
	    pre_processing_ukdmc2 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
            return $?
            ;;

	    "Kompsat-2")
            pre_processing_generic_optical "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
            return $?
            ;;

        "Kompsat-3")
            pre_processing_generic_optical "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
            return $?
            ;;

	    "Landsat-8")
	         pre_processing_generic_optical "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
            return $?
            ;;

        "SPOT-6")
            pre_processing_spot_pleiades "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
                return $?
                ;;

        "SPOT-7")
            pre_processing_spot_pleiades "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
                return $?
                ;;

        "PLEIADES")
            pre_processing_spot_pleiades "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
                return $?
                ;;

        "RapidEye")
            pre_processing_rapideye "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
                return $?
                ;;

        "Kompsat-5")
	        pre_processing_k5 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"
            return $?
	    ;;

        "VRSS1")
	    pre_processing_generic_optical "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"
            return $?
            ;;

        *)
	    return "${ERR_CALLPREPROCESS}"
	    ;;
esac

}


# function that get the list of contained bands depending on the mission data
function get_band_list(){
# function call bandListCsv=$( get_band_list "${prodname}" "${mission}" )
local prodname=$1
local mission=$2
local bandListCsv=""
case "$mission" in
        "PLEIADES")
            bandListCsv="Blue,Green,Red,NIR"
            ;;

        SPOT-[6-7])
            bandListCsv="Blue,Green,Red,NIR"
	    ;;

        "RapidEye")
            bandListCsv="Blue,Green,Red,RedEdge,NIR"
	    ;;

	    "Kompsat-5")
            # naming convention is K5>_<YYYYMMDDhhmmss>_<tttttt>_<nnnnn>_<o>_<MM><SS>_<PP>_<LLL> where PP is the polarization
            # always single pol
            bandListCsv=${prodname:38:2}
        ;;

        "VRSS1")
            bandListCsv="${prodname}_1,${prodname}_2,${prodname}_3,${prodname}_4"
            ;;

        *)
            return "${ERR_BAND_LIST}"
            ;;
esac
echo ${bandListCsv}
return 0
}

# function that computes the Multilook factor from target pixel spacing (i.e. master) and current one
function get_ml_factor() {

# function call get_ml_factor ${pixelSpacing} ${pixelSpacingMaster}

pixelSpacing=$1
pixelSpacingMaster=$2
local ml_factor=""

# if current pixel spacing is higher or equal to target one --> skip multilook
if (( $(bc <<< "$pixelSpacing >= $pixelSpacingMaster") )) ; then

    # skip multilook --> factor = 1
    ml_factor=1

# if current pixel spacing is lower or equal to target one --> do multilook
elif (( $(bc <<< "$pixelSpacing < $pixelSpacingMaster") )) ; then

    # multilook to be performed --> factor = floor($pixelSpacingMaster / $pixelSpacing)
    ml_factor=$(echo "scale=0; $pixelSpacingMaster / $pixelSpacing" | bc)

fi

echo $ml_factor


}

# function to calibrate optical image files
function calibrate_optical_TOA() {
# function call multispectral image file full path

local currentProd=$( basename $1 )
local imgsLocation=$( dirname $1 )
local inputExt=$2
local outputExt=$3
local gainbiasfile=$4
local solarilluminationsfile=$5
local other=$6
local outputfile="${currentProd##*/}"; outputfile="${outputfile%$inputExt}$outputExt"

#run OTB optical calibration
ciop-log "INFO" "Performing image calibration to ${outputfile}"
if [[ ! -z "$gainbiasfile" ]] && [[ ! -z "$solarilluminationsfile" ]]  ; then
    echo "otbcli_OpticalCalibration -in ${currentProd} -out ${outputfile} -acqui.gainbias ${gainbiasfile} -acqui.solarilluminations ${solarilluminationsfile} ${other} -level toa"
    otb_op=$( otbcli_OpticalCalibration -in ${currentProd} -out ${outputfile} -acqui.gainbias ${gainbiasfile} -acqui.solarilluminations ${solarilluminationsfile} ${other} -level toa -ram ${RAM_AVAILABLE})
else
    otb_op=$( otbcli_OpticalCalibration -in ${currentProd} -out ${outputfile} -level toa -ram ${RAM_AVAILABLE})
fi
#returnCode=$?
#[ $returnCode -eq 0 ] || return ${ERR_OTB}
echo ${outputfile}
}

# function that compares the pixel spacing and returns the greter one
function get_greater_pixel_spacing() {

# function call get_greater_pixel_spacing ${pixelSpacing} ${pixelSpacingMaster}

pixelSpacing=$1
pixelSpacingMaster=$2
local out_spacing=""

# if current pixel spacing is higher or equal to target one --> return current pixel spacing
if (( $(bc <<< "$pixelSpacing >= $pixelSpacingMaster") )) ; then

    out_spacing=$pixelSpacing

# if current pixel spacing is lower or equal to target one --> return master pixel spacing
elif (( $(bc <<< "$pixelSpacing < $pixelSpacingMaster") )) ; then

    out_spacing=$pixelSpacingMaster

fi

echo $out_spacing

}


function get_num_tiles() {
local prodname=$1
spot_xml=$(find ${prodname}/ -name 'DIM_*MS_*.XML')
numTiles=$(sed -n -e 's|^.*<NTILES>\(.*\)</NTILES>$|\1|p' ${spot_xml})
echo ${numTiles}
}

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
prodname=$retrievedProduct/$unzippedFolder

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

   cat << EOF > ${snap_request_filename}
<graph id="Graph">
<version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${prodname}</file>
      <formatName>SENTINEL-1</formatName>
    </parameters>
  </node>
  <node id="Calibration">
    <operator>Calibration</operator>
    <sources>
      <sourceProduct refid="Apply-Orbit-File"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <auxFile>Product Auxiliary File</auxFile>
      <externalAuxFile/>
      <outputImageInComplex>false</outputImageInComplex>
      <outputImageScaleInDb>false</outputImageScaleInDb>
      <createGammaBand>false</createGammaBand>
      <createBetaBand>false</createBetaBand>
      <selectedPolarisations/>
      <outputSigmaBand>true</outputSigmaBand>
      <outputGammaBand>false</outputGammaBand>
      <outputBetaBand>false</outputBetaBand>
    </parameters>
  </node>
${commentMlBegin}  <node id="Multilook">
    <operator>Multilook</operator>
    <sources>
      <sourceProduct refid="Calibration"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <nRgLooks>${ml_factor}</nRgLooks>
      <nAzLooks>${ml_factor}</nAzLooks>
      <outputIntensity>true</outputIntensity>
      <grSquarePixel>true</grSquarePixel>
    </parameters>
  </node> ${commentMlEnd}
  <node id="Terrain-Correction">
    <operator>Terrain-Correction</operator>
    <sources>
      ${commentMlBegin} <sourceProduct refid="Multilook"/> ${commentMlEnd}
      ${commentCalSrcBegin} <sourceProduct refid="Calibration"/> ${commentCalSrcEnd}
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <demName>SRTM 3Sec</demName>
      <externalDEMFile/>
      <externalDEMNoDataValue>0.0</externalDEMNoDataValue>
      <externalDEMApplyEGM>true</externalDEMApplyEGM>
      <demResamplingMethod>BILINEAR_INTERPOLATION</demResamplingMethod>
      <imgResamplingMethod>BILINEAR_INTERPOLATION</imgResamplingMethod>
      <pixelSpacingInMeter>10.0</pixelSpacingInMeter>
      <pixelSpacingInDegree>8.983152841195215E-5</pixelSpacingInDegree>
      <mapProjection>WGS84(DD)</mapProjection>
      <nodataValueAtSea>true</nodataValueAtSea>
      <saveDEM>false</saveDEM>
      <saveLatLon>false</saveLatLon>
      <saveIncidenceAngleFromEllipsoid>false</saveIncidenceAngleFromEllipsoid>
      <saveLocalIncidenceAngle>false</saveLocalIncidenceAngle>
      <saveProjectedLocalIncidenceAngle>false</saveProjectedLocalIncidenceAngle>
      <saveSelectedSourceBand>true</saveSelectedSourceBand>
      <outputComplex>false</outputComplex>
      <applyRadiometricNormalization>false</applyRadiometricNormalization>
      <saveSigmaNought>false</saveSigmaNought>
      <saveGammaNought>false</saveGammaNought>
      <saveBetaNought>false</saveBetaNought>
      <incidenceAngleForSigma0>Use projected local incidence angle from DEM</incidenceAngleForSigma0>
      <incidenceAngleForGamma0>Use projected local incidence angle from DEM</incidenceAngleForGamma0>
      <auxFile>Latest Auxiliary File</auxFile>
      <externalAuxFile/>
    </parameters>
  </node>
  <node id="LinearToFromdB">
    <operator>LinearToFromdB</operator>
    <sources>
      <sourceProduct refid="Terrain-Correction"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
    </parameters>
  </node>
  <node id="Apply-Orbit-File">
    <operator>Apply-Orbit-File</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <orbitType>Sentinel Precise (Auto Download)</orbitType>
      <polyDegree>3</polyDegree>
      <continueOnFail>true</continueOnFail>
    </parameters>
  </node>
${commentSbsBegin}  <node id="Subset">
    <operator>Subset</operator>
    <sources>
      <sourceProduct refid="LinearToFromdB"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <region/>
      <geoRegion>${subsettingBoxWKT}</geoRegion>
      <subSamplingX>1</subSamplingX>
      <subSamplingY>1</subSamplingY>
      <fullSwath>false</fullSwath>
      <tiePointGridNames/>
      <copyMetadata>true</copyMetadata>
    </parameters>
  </node>  ${commentSbsEnd}
  <node id="Write">
    <operator>Write</operator>
    <sources>
      ${commentSbsBegin} <sourceProduct refid="Subset"/> ${commentSbsEnd}
      ${commentDbSrcBegin} <sourceProduct refid="LinearToFromdB"/> ${commentDbSrcEnd}
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outprod}.dim</file>
      <formatName>BEAM-DIMAP</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="9.0" y="128.0"/>
    </node>
    <node id="Calibration">
      <displayPosition x="200.0" y="129.0"/>
    </node>
    <node id="Multilook">
	  <displayPosition x="291.0" y="129.0"/>
    </node>
    <node id="Terrain-Correction">
      <displayPosition x="480.0" y="129.0"/>
    </node>
    <node id="LinearToFromdB">
      <displayPosition x="623.0" y="129.0"/>
    </node>
    <node id="Apply-Orbit-File">
      <displayPosition x="88.0" y="129.0"/>
    </node>
    <node id="Subset">
      <displayPosition x="751.0" y="127.0"/>
    </node>
    <node id="Write">
		<displayPosition x="850.0" y="129.0"/>
    </node>
  </applicationData>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}
}


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
    if [[ "${performOpticalCalibration}" = true ]]; then
        for tif in $(cat "${tifList}"); do
            if [[ $tif != *LC*_B1[0,1]* ]]; then
                ciop-log "INFO" "Performing radiometric calibration for $tif"
                cd $( dirname ${tif})
                metadatafile=$(ls ${prodname}/*_MTL.txt)
                outputfile="${tif%.TIF}_toa.tif"
                rio toa reflectance ${tif} ${metadatafile} ${outputfile}
                rm $tif
                mv $outputfile $tif
            fi
            cd -
        done
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
    if [ ${prodBasename} != ${vrss1_name} ]; then
        # in this case the product name is not common
        # to the base band names ---> rename all bands
        for bix in 1 2 3 4 ;
        do
           currentTif=$(ls "${prodname}"/*_"${bix}".tif)
           mv ${currentTif} ${prodname}/${prodBasename}_${bix}.tif
           [[ $bix == "1"  ]] && ls ${prodname}/${prodBasename}_${bix}.tif > $tifList || ls ${prodname}/${prodBasename}_${bix}.tif >> $tifList
        done
    else
        ls "${prodname}"/*_1.tif > $tifList
        ls "${prodname}"/*_2.tif >> $tifList
        ls "${prodname}"/*_3.tif >> $tifList
        ls "${prodname}"/*_4.tif >> $tifList
    fi
else
    return ${ERR_PREPROCESS}
fi

for tif in $(cat "${tifList}"); do
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
else:
    # prepare the SNAP request
    SNAP_REQUEST=$( create_snap_request_stack "${filesListCSV}" "${outProdStack}" "${numProd}" )
    [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
    [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
    # report activity in the log
    ciop-log "INFO" "Invoking SNAP-gpt request file for products stacking"
    # invoke the ESA SNAP toolbox
    gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
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

function create_snap_request_linear_to_dB(){
# function call: create_snap_request_linear_to_dB "${inputfile}" "${outputfile}"

# function which creates the actual request from
# a template and returns the path to the request

# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "2" ] ; then
    return ${SNAP_REQUEST_ERROR}
fi

local inputfile=$1
local outputfile=$2
local filename="${outputfile##*/}"
local ext="${filename##*.}"
local format=""
if [[ "$ext" == "dim" ]]; then
    format="BEAM-DIMAP"
elif [[ "$ext" == "tif" ]]; then
    format="GeoTIFF-BigTIFF"
else
    return ${SNAP_REQUEST_ERROR}
fi


#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${inputfile}</file>
    </parameters>
  </node>
  <node id="BandMaths">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>band_1</name>
          <type>uint8</type>
          <expression>if fneq(band_1,0) then max(20*log10(band_1),1) else 0</expression>
          <description/>
          <unit/>
          <noDataValue>0.0</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="BandMaths"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outputfile}</file>
      <formatName>${format}</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
    <node id="BandMaths">
      <displayPosition x="247.0" y="132.0"/>
    </node>
    <node id="Write">
            <displayPosition x="455.0" y="135.0"/>
    </node>
  </applicationData>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}

}

function create_snap_request_stack(){
# function call: create_snap_request_stack "${inputfiles_list}" "${outProdDIM}" "${numProd}"

    # function which creates the actual request from
    # a template and returns the path to the request

    # get number of inputs
    inputNum=$#
    # check on number of inputs
    if [ "$inputNum" -ne "3" ] ; then
        return ${SNAP_REQUEST_ERROR}
    fi

    local inputfiles_list=$1
    local outProdDIM=$2
    local numProd=$3

    #sets the output filename
    snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

   cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="ProductSet-Reader">
    <operator>ProductSet-Reader</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <fileList>${inputfiles_list}</fileList>
    </parameters>
  </node>
<node id="CreateStack">
    <operator>CreateStack</operator>
    <sources>
      <sourceProduct.$numProd refid="ProductSet-Reader"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <masterBands/>
      <sourceBands/>
      <resamplingType>NONE</resamplingType>
      <extent>Master</extent>
      <initialOffsetMethod>Product Geolocation</initialOffsetMethod>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="CreateStack"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outProdDIM}.dim</file>
      <formatName>BEAM-DIMAP</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Write">
            <displayPosition x="455.0" y="135.0"/>
    </node>
    <node id="CreateStack">
      <displayPosition x="240.0" y="132.0"/>
    </node>
    <node id="ProductSet-Reader">
      <displayPosition x="39.0" y="131.0"/>
    </node>
  </applicationData>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}

}


# function for renaming all the bands
function create_snap_request_rename_all_bands(){
# function call create_snap_request_rename_all_bands "${inputProdDIM}" "${currentBandsListTXT}" "${targetBandsNamesListTXT}" "${outProdRename}"

# function which creates the actual request from
# a template and returns the path to the request

# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "4" ] ; then
    return ${SNAP_REQUEST_ERROR}
fi

local inputProdDIM=$1
local currentBandsListTXT=$2
local targetBandsNamesListTXT=$3
local outProdRename=$4

# loop to fill xml operator to rename bands and merge them
local bandsSetRename=${TMPDIR}/bandSetRename.txt
local bandMerge=${TMPDIR}/bandSetMerge.txt
cat << EOF > ${bandMerge}
  <node id="BandMerge">
    <operator>BandMerge</operator>
    <sources>
EOF

declare -a currentBandsList
declare -a targetBandsNamesList
for currBand in $( cat ${currentBandsListTXT}) ; do
    currentBandsList+=("${currBand}")
done
for targetBand in $( cat ${targetBandsNamesListTXT}) ; do
    targetBandsNamesList+=("${targetBand}")
done
currentBandsList_num=${#currentBandsList[@]}
targetBandsNamesList_num=${#targetBandsNamesList[@]}

# loop on band names to fill band list
let "currentBandsList_num-=1"
for index in `seq 0 $currentBandsList_num`;
do
    bandSetRenameTmp=${TMPDIR}/bandSetRenameTmp.txt
    cat << EOF > ${bandSetRenameTmp}
    <node id="BandMaths($index)">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>${targetBandsNamesList[${index}]}</name>
          <type>float32</type>
          <expression>${currentBandsList[${index}]}</expression>
          <description/>
          <unit/>
          <noDataValue>0.0</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
EOF
    if [ $index -eq 0  ] ; then
        cat ${bandSetRenameTmp} > ${bandsSetRename}
    else
        cat ${bandSetRenameTmp} >> ${bandsSetRename}
    fi
    rm ${bandSetRenameTmp}

    bandSetMergeTmp=${TMPDIR}/bandSetMergeTmp.txt
    num=""
    [ $index -ne 0 ] && num=.$index
        cat << EOF > ${bandSetMergeTmp}
<sourceProduct$num refid="BandMaths($index)"/>
EOF
    cat ${bandSetMergeTmp} >> ${bandMerge}
    rm ${bandSetMergeTmp}
done

bandSetMergeTmp=${TMPDIR}/bandSetMergeTmp.txt
cat << EOF > ${bandSetMergeTmp}
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <geographicError>1.0E-5</geographicError>
    </parameters>
  </node>
EOF

cat ${bandSetMergeTmp} >> ${bandMerge}
rm ${bandSetMergeTmp}

#sets the output filename
    snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${inputProdDIM}</file>
    </parameters>
  </node>
EOF

cat ${bandsSetRename} >> ${snap_request_filename}
cat ${bandMerge} >> ${snap_request_filename}

tmpWrite=${TMPDIR}/writeTmp.txt
cat << EOF > ${tmpWrite}
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="BandMerge"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outProdRename}.dim</file>
      <formatName>BEAM-DIMAP</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Write">
            <displayPosition x="455.0" y="135.0"/>
    </node>
    <node id="BandMerge">
      <displayPosition x="240.0" y="132.0"/>
    </node>
    <node id="Read">
      <displayPosition x="39.0" y="131.0"/>
    </node>
  </applicationData>
</graph>
EOF

cat ${tmpWrite} >> ${snap_request_filename}
rm ${tmpWrite}
echo "${snap_request_filename}"
return 0

}


function create_snap_request_rsmpl_rprj_sbs() {

# function call create_snap_request_rsmpl_rprj_sbs "${prodname}" "${performResample}" "${target_spacing}" "${performCropping}" "${subsettingBoxWKT}" "${sourceBandsList}" "${outProd}"

# function which creates the actual request from
# a template and returns the path to the request

inputNum=$#
[ "$inputNum" -ne 7 ] && return ${ERR_PREPROCESS}

local prodname=$1
local performResample=$2
local target_spacing=$3
local performCropping=$4
local subsettingBoxWKT=$5
local sourceBandsList=$6
local outprod=$7

local commentRsmpBegin=""
local commentRsmpEnd=""
local commentReadSrcBegin=""
local commentReadSrcEnd=""
local commentSbsBegin=""
local commentSbsEnd=""
local commentMlBegin=""
local commentMlEnd=""
local commentProjSrcBegin=""
local commentProjSrcEnd=""

local beginCommentXML="<!--"
local endCommentXML="-->"

# check for resampling operator usage
if [ "${performResample}" = false ] ; then
    commentRsmpBegin="${beginCommentXML}"
    commentRsmpEnd="${endCommentXML}"
else
    commentReadSrcBegin="${beginCommentXML}"
    commentReadSrcEnd="${endCommentXML}"
fi
# check for subset operator usage
if [ "${performCropping}" = false ] ; then
    commentSbsBegin="${beginCommentXML}"
    commentSbsEnd="${endCommentXML}"
else
    commentProjSrcBegin="${beginCommentXML}"
    commentProjSrcEnd="${endCommentXML}"
fi

#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

   cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${prodname}</file>
    </parameters>
  </node>
${commentRsmpBegin}  <node id="Resample">
    <operator>Resample</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <referenceBand/>
      <targetWidth/>
      <targetHeight/>
      <targetResolution>${target_spacing}</targetResolution>
      <upsampling>Nearest</upsampling>
      <downsampling>First</downsampling>
      <flagDownsampling>First</flagDownsampling>
      <resampleOnPyramidLevels>false</resampleOnPyramidLevels>
    </parameters>
  </node> ${commentRsmpEnd}
  <node id="Reproject">
    <operator>Reproject</operator>
    <sources>
${commentRsmpBegin}      <sourceProduct refid="Resample"/> ${commentRsmpEnd}
${commentReadSrcBegin}   <sourceProduct refid="Read"/> ${commentReadSrcEnd}
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <wktFile/>
      <crs>GEOGCS[&quot;WGS84(DD)&quot;, &#xd;
  DATUM[&quot;WGS84&quot;, &#xd;
    SPHEROID[&quot;WGS84&quot;, 6378137.0, 298.257223563]], &#xd;
  PRIMEM[&quot;Greenwich&quot;, 0.0], &#xd;
  UNIT[&quot;degree&quot;, 0.017453292519943295], &#xd;
  AXIS[&quot;Geodetic longitude&quot;, EAST], &#xd;
  AXIS[&quot;Geodetic latitude&quot;, NORTH]]</crs>
      <resampling>Nearest</resampling>
      <referencePixelX/>
      <referencePixelY/>
      <easting/>
      <northing/>
      <orientation/>
      <pixelSizeX/>
      <pixelSizeY/>
      <width/>
      <height/>
      <tileSizeX/>
      <tileSizeY/>
      <orthorectify>false</orthorectify>
      <elevationModelName/>
      <noDataValue>NaN</noDataValue>
      <includeTiePointGrids>true</includeTiePointGrids>
      <addDeltaBands>false</addDeltaBands>
    </parameters>
  </node>
${commentSbsBegin}  <node id="Subset">
    <operator>Subset</operator>
    <sources>
      <sourceProduct refid="Reproject"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <region/>
      <geoRegion>${subsettingBoxWKT}</geoRegion>
      <subSamplingX>1</subSamplingX>
      <subSamplingY>1</subSamplingY>
      <fullSwath>false</fullSwath>
      <tiePointGridNames/>
      <copyMetadata>true</copyMetadata>
    </parameters>
  </node> ${commentSbsEnd}
  <node id="BandSelect">
    <operator>BandSelect</operator>
    <sources>
      ${commentSbsBegin} <sourceProduct refid="Subset"/> ${commentSbsEnd}
      ${commentProjSrcBegin} <sourceProduct refid="Reproject"/> ${commentProjSrcEnd}
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <selectedPolarisations/>
      <sourceBands>${sourceBandsList}</sourceBands>
      <bandNamePattern/>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
       <sourceProduct refid="BandSelect"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outprod}.dim</file>
      <formatName>BEAM-DIMAP</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Write">
            <displayPosition x="455.0" y="135.0"/>
    </node>
    <node id="BandSelect">
      <displayPosition x="400.0" y="136.0"/>
    </node>
    <node id="Subset">
      <displayPosition x="327.0" y="136.0"/>
    </node>
    <node id="Reproject">
      <displayPosition x="231.0" y="137.0"/>
    </node>
    <node id="Resample">
      <displayPosition x="140.0" y="133.0"/>
    </node>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
  </applicationData>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}
}


function main() {

    #get input product list and convert it into an array
    # It should contain only the Master product
    local -a inputfiles=($@)
    #get the number of products to be processed
    inputfilesNum=$#
    # check if number of products is 1 (only master)
    [ "$inputfilesNum" -ne "1" ] && exit $ERR_WRONGINPUTNUM
    local master=${inputfiles[0]}
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "Master product reference provided at input: ${master}"

    #get input slave(s) product
    local slave="`ciop-getparam slave`"
    # run a check on the slave value, it can't be empty
    [ -z "$slave" ] && exit $ERR_NOPROD
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "Slave(s) product reference provided at input: ${slave}"
    # slaves list from csv to space separated value
    inputSlaveList=($( echo "${slave}" | sed 's|,| |g' ))
    slavesNum=${#inputSlaveList[@]}
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "Number of input slave(s): ${slavesNum}"
    # check if number of products is less than 1
    [ "$slavesNum" -lt "1" ] && exit $ERR_WRONGINPUTNUM

    # retrieve the parameters value from workflow or job default value
    performOpticalCalibration="`ciop-getparam performOpticalCalibration`"
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "The performOpticalCalibration flag is set to ${performOpticalCalibration}"

    # retrieve the parameters value from workflow or job default value
    performCropping="`ciop-getparam performCropping`"
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "The performCropping flag is set to ${performCropping}"

    # retrieve the parameters value from workflow or job default value
    SubsetBoundingBox="`ciop-getparam SubsetBoundingBox`"
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "The selected subset bounding box data is: ${SubsetBoundingBox}"

    ### SUBSETTING BOUNDING BOX DEFINITION IN WKT FORMAT
    local subsettingBoxWKT="POLYGON ((-180 -90, 180 -90, 180 90, -180 90, -180 -90))"
    if [ "${performCropping}" = true ] ; then
        # bounding box from csv to space separated value
        SubsetBoundingBox=$( echo "${SubsetBoundingBox}" | sed 's|,| |g' )
        #convert subset bounding box into WKT format
        SubsetBoundingBoxArray=($SubsetBoundingBox)
        lon_min="${SubsetBoundingBoxArray[0]}"
        lat_min="${SubsetBoundingBoxArray[1]}"
        lon_max="${SubsetBoundingBoxArray[2]}"
        lat_max="${SubsetBoundingBoxArray[3]}"
        subsettingBoxWKT="POLYGON (("${lon_min}" "${lat_min}", "${lon_max}" "${lat_min}", "${lon_max}" "${lat_max}", "${lon_min}" "${lat_max}", "${lon_min}" "${lat_min}"))"

        # log the value, it helps debugging.
        # the log entry is available in the process stderr
        ciop-log "DEBUG" "WKT subsettingBox = ${subsettingBoxWKT}"

    fi

    pixelSpacingMaster=""
    # loop on master + slave products for pre-processing
    # index goes from 0 to slavesNum (so are processed slavesNum + 1 product to include Master)
    # if prodIndex = 0 then the pre processing is done for Master
    # if prodIndex > 0 then the pre precessinf is done for inputSlaveList[prodIndex-1]
    for prodIndex in `seq 0 $slavesNum`;
    do
        ### GET CURRENT DATA PRODUCT

	# declare local master
	local isMaster=""
	# Master case
	if [ $prodIndex -eq 0  ] ; then
	    #current product
            currentProduct=${master}
            # master flag
	    isMaster=1
        else
	    let "tmpIndex=prodIndex-1"
	    #current product
            currentProduct=${inputSlaveList[$tmpIndex]}
	    # master flag
            isMaster=0
        fi
        # run a check on the value, it can't be empty
        [ -z "$currentProduct" ] && exit $ERR_NOPROD
        # log the value, it helps debugging.
        # the log entry is available in the process stderr
        ciop-log "DEBUG" "The product reference to be used is: ${currentProduct}"
        # report product retrieving activity in log
        ciop-log "INFO" "Retrieving ${currentProduct}"
        # retrieve product to the local temporary folder TMPDIR provided by the framework (this folder is only used by this process)
        # the utility returns the local path of the retrieved product
        retrievedProduct=$( get_data "${currentProduct}" "${TMPDIR}" )
        if [ $? -ne 0  ] ; then
            cat ${TMPDIR}/ciop_copy.stderr
            return $ERR_NORETRIEVEDPROD
        fi
#        unzippedFolder=$(ls $retrievedProduct)
#        # log the value, it helps debugging.
#        # the log entry is available in the process stderr
#        ciop-log "DEBUG" "unzippedFolder: ${unzippedFolder}"
#
#        # retrieved product pointing to the unzipped folder
#        retrievedProduct=$retrievedProduct/$unzippedFolder
        prodname=$( basename "$retrievedProduct" )
        # report activity in the log
        ciop-log "INFO" "Product correctly retrieved: ${prodname}"

        ### EXTRACT MISSION IDENTIFIER

        # report activity in the log
        ciop-log "INFO" "Retrieving mission identifier from product name"
        mission=$( mission_prod_retrieval "${prodname}")
        [ $? -eq 0 ] || return ${ERR_GETMISSION}
        # log the value, it helps debugging.
        # the log entry is available in the process stderr
        ciop-log "INFO" "Retrieved mission identifier: ${mission}"

        ### PRODUCT TYPE CHECK

        # report activity in the log
        ciop-log "INFO" "Checking product type from product name"
        #get product type from product name
        prodType=$( check_product_type "${retrievedProduct}" "${mission}")
        returnCode=$?
        [ $returnCode -eq 0 ] || return $returnCode
        # log the value, it helps debugging.
        # the log entry is available in the process stderr
        ciop-log "INFO" "Retrieved product type: ${prodType}"

	### GET PIXEL SPACING FROM MISSION IDENTIFIER OF MASTER PRODUCT

	# report activity in the log
	ciop-log "INFO" "Getting pixel spacing from mission identifier"
        #get pixel spacing from mission identifier
        pixelSpacing=$( get_pixel_spacing "${mission}" "${prodname}" "${prodType}")
        returnCode=$?
        [ $returnCode -eq 0 ] || return $returnCode
        if [ $isMaster -eq 1 ] ; then
	   pixelSpacingMaster=$pixelSpacing
	   # log the value, it helps debugging.
           # the log entry is available in the process stderr
           ciop-log "INFO" "Master pixel spacing: ${pixelSpacingMaster} m"
	else
	   # log the value, it helps debugging.
           # the log entry is available in the process stderr
           ciop-log "INFO" "Slave pixel spacing: ${pixelSpacing} m"
	fi

        ### PRE-PROCESSING DEPENDING ON MISSION DATA

        # report activity in the log
        ciop-log "INFO" "Running pre-processing for ${prodname}"
        pre_processing "${retrievedProduct}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
        returnCode=$?
        [ $returnCode -eq 0 ] || return $returnCode
        # Publish results
        # NOTE: it is assumed that the "pre_processing" function always provides results in tar format in $OUTPUTDIR
        # report activity in the log
        ciop-log "INFO" "Publishing results for ${prodname}"
        # if master rename the tar output to allow following processing to identify it
        if [ $isMaster -eq 1 ] ; then
	    out_prodname=$( ls "${OUTPUTDIR}"/*.tar )
            mv ${out_prodname} ${out_prodname}.master
	fi
	ciop-publish ${OUTPUTDIR}/*.*

        #cleanup
        rm -rf ${retrievedProduct} ${OUTPUTDIR}/*.*

    done

    #cleanup
    rm -rf ${TMPDIR}

    return ${SUCCESS}
}

# create the output folder to store the output products and export it
mkdir -p ${TMPDIR}/output
export OUTPUTDIR=${TMPDIR}/output
# debug flag setting
export DEBUG=0

# loop on input file to create a product array that will be processed by the main process
declare -a inputfiles
while read inputfile; do
    inputfiles+=("${inputfile}") # Array append
done
# run main process
main ${inputfiles[@]}
res=$?
[ ${res} -ne 0 ] && exit ${res}

exit $SUCCESS
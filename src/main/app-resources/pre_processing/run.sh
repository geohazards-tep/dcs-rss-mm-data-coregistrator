#!/bin/bash

# source the ciop functions (e.g. ciop-log, ciop-getparam)
source ${ciop_job_include}

# set the environment variables to use ORFEO toolbox
source $_CIOP_APPLICATION_PATH/otb/otb_include.sh

# set the environment variables to use ESA SNAP toolbox
#export SNAP_HOME=$_CIOP_APPLICATION_PATH/common/snap
#export PATH=${SNAP_HOME}/bin:${PATH}
source $_CIOP_APPLICATION_PATH/gpt/snap_include.sh

#Import modules for the pre-processing of images
source $_CIOP_APPLICATION_PATH/pre_processing/modules/generic_optical.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/k5.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/spot_pleiades.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/kanopus.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/rapideye.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/alos.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/rs2.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/s2.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/ukdmc.sh
source $_CIOP_APPLICATION_PATH/pre_processing/modules/s1.sh

## put /opt/anaconda/bin ahead to the PATH list to ensure gdal to point to the anaconda installation dir
export PATH=/opt/anaconda/bin:${PATH}
#export PATH=/home/rssuser/.conda/envs/csw/bin:${PATH}
#export PATH=/home/rssuser/.conda/envs/l8reflectanceTesting/bin:${PATH}

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
ERR_CALIB=19
ERR_CONVERT=20
ERR_GETTILENUM=21


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
	    ${ERR_CALIB})          	  msg="Error during calibration procedure";;
	    ${ERR_CONVERT})           msg="Convert failed to process";;
	    ${ERR_GETTILENUM})         msg="Error while retrieving the number of tiles of an image";;
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

  if [[ "${mission}" == "GF2" ]]; then
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      # assumption is that the product has .tar extension
      if  [[ "$ext" == "tar" ]]; then
          ciop-log "INFO" "Running command: tar xf $retrievedProduct *MSS2.xml"
          tar xf $retrievedProduct *MSS2.xml
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          prodTypeName=$(sed -n -e 's|^.*<ProductLevel>\(.*\)</ProductLevel>$|\1|p' *MSS2.xml)
          rm -f *MSS2.xml
      else
	  ciop-log "ERROR" "Failed to get product type from : ${retrievedProduct}"
	  ciop-log "ERROR" "Product extension not equal to the expected"
          return $ERR_WRONGPRODTYPE
      fi
      [[ "$prodTypeName" != "LEVEL2A" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Kanopus-V" ]]; then
        mss_test=$(echo "${productName}" | grep "MSS")
	[[ "$mss_test" != "" ]] && prodTypeName="MSS"  || return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Alos-2" ]]; then
        prodTypeName=""
        # check if ALOS2 product is a folder
        if [[ -d "${retrievedProduct}" ]]; then
        # check if ALOS2 folder contains a zip file
           ALOS_ZIP=$(ls ${retrievedProduct} | egrep '^.*ALOS2.*.zip$')
           # if doesn't contain a zip it should be already uncompressed -> search summary file into the folder
        if [[ -z "$ALOS_ZIP" ]]; then
           prodTypeName="$( cat ${retrievedProduct}/summary.txt | sed -n -e 's|^.*_ProcessLevel=\"\(.*\)\".*$|\1|p')"
        # extract summary file from compressed archive
           else
               prodTypeName="$(unzip -p ${retrievedProduct}/$ALOS_ZIP summary.txt | sed -n -e 's|^.*_ProcessLevel=\"\(.*\)\".*$|\1|p')"
           fi
        fi
        [[ -z "$prodTypeName" ]] && ciop-log "ERROR" "Failed to get product type from : $retrievedProduct"
        [[ "$prodTypeName" != "1.5" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Radarsat-2" ]]; then
      #naming convention <RS2_BeamMode_Date_Time_Polarizations_ProcessingLevel>
      prodTypeName=${productName:(-3)}
      [[ "$prodTypeName" != "SGF" ]] && return $ERR_WRONGPRODTYPE
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
        prod_basename_substr_9=${prod_basename:0:9}
        [ "${prod_basename_substr_3}" = "S1A" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S1B" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S2A" ] && mission="Sentinel-2"
        [ "${prod_basename_substr_3}" = "S2B" ] && mission="Sentinel-2"
#        [ "${prod_basename_substr_3}" = "K5_" ] && mission="Kompsat-5"
        [ "${prod_basename_substr_3}" = "GF2" ] && mission="GF2"
        [ "${prod_basename_substr_3}" = "K3_" ] && mission="Kompsat-3"
        [ "${prod_basename_substr_3}" = "LC8" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "LS08" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "MSC_" ] && mission="Kompsat-2"
        [ "${prod_basename_substr_4}" = "FCGC" ] && mission="PLEIADES"
        [ "${prod_basename_substr_5}" = "U2007" ] && mission="UK-DMC2"
        [ "${prod_basename_substr_5}" = "ORTHO" ] && mission="UK-DMC2"
#        [ "${prod_basename}" = "Resurs-P" ] && mission="Resurs-P"
#        [ "${prod_basename_substr_4}" = "RS2_" ] && mission="Radarsat-2"
        if [[ "${prod_basename_substr_9}" == "KANOPUS_V" ]] || [[ "${prod_basename_substr_9}" == "KANOPUS-V" ]] || [[ "${prod_basename_substr_9}" == "Kanopus-V" ]] || [[ "${prod_basename_substr_9}" == "Kanopus_V" ]] ; then
            mission="Kanopus-V"
        fi
#        alos2_test=$(echo "${prod_basename}" | grep "ALOS2")
#        [ "${alos2_test}" = "" ] || mission="Alos-2"
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
        vrss1_test_1=$(echo "${prod_basename}" | grep "VRSS1")
        vrss1_test_2=$(echo "${prod_basename}" | grep "VRSS-1")
        vrss1_test_3=$(ls "${retrievedProduct}" | grep "VRSS")
        if [[ "${vrss1_test_1}" != "" ]] || [[ "${vrss1_test_2}" != "" ]] || [[ "${vrss1_test_3}" != "" ]]; then
            mission="VRSS1"
        fi

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
            echo 10
            ;;
#            product_xml=$(find ${retrievedProduct}/ -name 'VRSS*_L2B_*[0-9].xml')
#            ciop-log "DEBUG" "metadata file is $product_xml"
#            pixSpac=$( cat ${product_xml} | grep pixelSpacing | sed -n -e 's|^.*<pixelSpacing>\(.*\)</pixelSpacing>|\1|p' )
#            echo  $pixSpac | awk '{ print sprintf("%.9f", $1); }'
#            ;;
        "GF2")
            echo 10
            ;;

        "Kanopus-V")
            echo 12
            ;;

        "Alos-2")
            echo 10
            ;;

        "Radarsat-2")
            product_xml=$(find ${retrievedProduct}/ -name 'product.xml')
            pixSpac=$( cat ${product_xml} | grep sampledPixelSpacing | sed -n -e 's|^.*<sampledPixelSpacing .*>\(.*\)</sampledPixelSpacing>|\1|p' )
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
	        pre_processing_generic_optical "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
            return $?
            ;;

        "GF2")
	        pre_processing_generic_optical "${prodname}" "${mission}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
            return $?
            ;;

        "Kanopus-V")
	        pre_processing_kanopus "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}" "${performOpticalCalibration}"
            return $?
            ;;

        "Alos-2")
	        pre_processing_alos "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"
            return $?
	    ;;

        "Radarsat-2")
            pre_processing_rs2 "${prodname}" "${pixelSpacing}" "${pixelSpacingMaster}" "${performCropping}" "${subsettingBoxWKT}"
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

        "Kanopus-V")
            bandListCsv="Blue,Green,Red,NIR"
	    ;;

        "Radarsat-2")
            local isDualPol=0
            local isQuadPol=0
            if [[ $( echo ${prodname} | grep "HH_HV_VH_VV" ) != "" ]] ; then
                 bandListCsv="Sigma0_HH_db,Sigma0_HV_db,Sigma0_VH_db,Sigma0_VV_db"
                 isQuadPol=1
            elif [[ $( echo ${prodname} | grep "HH_HV" ) != "" ]] && [ $isQuadPol -eq 0 ]; then
                 bandListCsv="Sigma0_HH_db,Sigma0_HV_db"
                 isDualPol=1
            elif [[ $( echo ${prodname} | grep "VV_VH" ) != "" ]] && [ $isQuadPol -eq 0 ]; then
                 bandListCsv="Sigma0_VV_db,Sigma0_VH_db"
                 isDualPol=1
            elif [[ $( echo ${prodname} | grep "HH" ) != "" ]] && [ $isQuadPol -eq 0 ] && [ $isDualPol -eq 0 ]; then
                 bandListCsv="Sigma0_HH_db"
            elif [[ $( echo ${prodname} | grep "VV" ) != "" ]] && [ $isQuadPol -eq 0 ] && [ $isDualPol -eq 0 ]; then
                 bandListCsv="Sigma0_VV_db"
	        fi
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
    otb_op=$( otbcli_OpticalCalibration -in ${currentProd} -out ${outputfile} -acqui.gainbias ${gainbiasfile} -acqui.solarilluminations ${solarilluminationsfile} ${other} -level toa -ram ${RAM_AVAILABLE})
else
    otb_op=$( otbcli_OpticalCalibration -in ${currentProd} -out ${outputfile} -level toa -ram ${RAM_AVAILABLE})
fi
[ -f ${outputfile} ] && echo ${outputfile} || return $ERR_CALIB
}

function unpack_geotiff() {
# function to unpack compressed geotiff files

local geotiffProd=$1
local outputfile=${TMPDIR}/$(basename ${geotiffProd})

check_packed=$(gdalinfo $geotiffProd | grep COMPRESSION=LZW)
if [[ $check_packed == "COMPRESSION=LZW" ]]; then
    ciop-log "INFO" "Unpacking GeoTiff file"
    gdal_translate ${geotiffProd} ${outputfile} -of GTiff
    [ $? -eq 0 ] || return $ERR_GDAL
    mv ${outputfile} ${geotiffProd}
fi
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
[ -z "$numTiles" ] && return $ERR_GETTILENUM || echo ${numTiles}
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
SNAP_gpt_template="$_CIOP_APPLICATION_PATH/pre_processing/templates/snap_request_linear_to_dB.xml"

sed -e "s|%%inputfile%%|${inputfile}|g" \
-e "s|%%outputfile%%|${outputfile}|g" \
-e "s|%%format%%|${format}|g"  $SNAP_gpt_template > $snap_request_filename

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
    SNAP_gpt_template="$_CIOP_APPLICATION_PATH/pre_processing/templates/snap_request_stack.xml"

    sed -e "s|%%inputfiles_list%%|${inputfiles_list}|g" \
    -e "s|%%numProd%%|${numProd}|g" \
    -e "s|%%outProdDIM%%|${outProdDIM}|g"  $SNAP_gpt_template > $snap_request_filename
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
SNAP_gpt_template="$_CIOP_APPLICATION_PATH/pre_processing/templates/snap_request_rsmpl_rprj_sbs.xml"

sed -e "s|%%prodname%%|${prodname}|g" \
-e "s|%%commentRsmpBegin%%|${commentRsmpBegin}|g" \
-e "s|%%target_spacing%%|${target_spacing}|g" \
-e "s|%%commentRsmpEnd%%|${commentRsmpEnd}|g" \
-e "s|%%commentReadSrcBegin%%|${commentReadSrcBegin}|g" \
-e "s|%%commentReadSrcEnd%%|${commentReadSrcEnd}|g" \
-e "s|%%commentSbsBegin%%|${commentSbsBegin}|g" \
-e "s|%%subsettingBoxWKT%%|${subsettingBoxWKT}|g" \
-e "s|%%commentSbsEnd%%|${commentSbsEnd}|g" \
-e "s|%%commentProjSrcBegin%%|${commentProjSrcBegin}|g" \
-e "s|%%commentProjSrcEnd%%|${commentProjSrcEnd}|g" \
-e "s|%%sourceBandsList%%|${sourceBandsList}|g" \
-e "s|%%outprod%%|${outprod}|g"  $SNAP_gpt_template > $snap_request_filename

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
#!/bin/bash

# source the ciop functions (e.g. ciop-log, ciop-getparam)
source ${ciop_job_include}

# set the environment variables to use ESA SNAP toolbox
#export SNAP_HOME=$_CIOP_APPLICATION_PATH/common/snap
#export PATH=${SNAP_HOME}/bin:${PATH}
source $_CIOP_APPLICATION_PATH/gpt/snap_include.sh

# define the exit codes
SUCCESS=0
SNAP_REQUEST_ERROR=1
ERR_SNAP=2
ERR_NODATA=3
ERR_NORETRIEVEDPROD=4
ERR_GETMISSION=5
ERR_GETDATA=6
ERR_WRONGINPUTNUM=7
ERR_GETPRODTYPE=8
ERR_WRONGPRODTYPE=9
ERR_GETPRODMTD=10
ERR_PCONVERT=11
ERR_PROPERTIES_FILE_CREATOR=12


# add a trap to exit gracefully
function cleanExit ()
{
    local retval=$?
    local msg=""

    case ${retval} in
        ${SUCCESS})                     msg="Processing successfully concluded";;
        ${SNAP_REQUEST_ERROR})          msg="Could not create snap request file";;
        ${ERR_SNAP})                    msg="SNAP failed to process";;
        ${ERR_NODATA})                  msg="Could not retrieve the input data";;
        ${ERR_NORETRIEVEDPROD})         msg="Product not correctly downloaded";;
        ${ERR_GETMISSION})              msg="Error while retrieving mission name from product name or mission data not supported";;
        ${ERR_GETDATA})                 msg="Error while discovering product";;
        ${ERR_WRONGINPUTNUM})           msg="Number of input products less than 1";;
        ${ERR_GETPRODTYPE})             msg="Error while retrieving product type info from input product name";;
        ${ERR_WRONGPRODTYPE})           msg="Product type not supported";;
        ${ERR_GETPRODMTD})              msg="Error while retrieving metadata file from product";;
        ${ERR_PCONVERT})                msg="PCONVERT failed to process";;
	${ERR_PROPERTIES_FILE_CREATOR}) msg="Could not create the .properties file";;
        *)                              msg="Unknown error";;
    esac

   [ ${retval} -ne 0 ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
   if [ $DEBUG -ne 1 ] ; then
        [ ${retval} -ne 0 ] && hadoop dfs -rmr $(dirname "${inputfiles[0]}")
   fi
   exit ${retval}

}


function create_snap_request_stack(){
# function call: create_snap_request_stack "${inputfilesDIM_list}" "${outProdTIF}" "${numProd}"

    # function which creates the actual request from
    # a template and returns the path to the request

    # get number of inputs
    inputNum=$#
    # check on number of inputs
    if [ "$inputNum" -ne "3" ] ; then
        return ${SNAP_REQUEST_ERROR}
    fi

    local inputfilesDIM_list=$1
    local outProdTIF=$2
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
      <fileList>${inputfilesDIM_list}</fileList>
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
      <resamplingType>BILINEAR_INTERPOLATION</resamplingType>
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
      <file>${outProdTIF}</file>
      <formatName>GeoTIFF-BigTIFF</formatName>
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


function propertiesFileCratorTIF(){
# function call propertiesFileCratorTIF "${outputProdTIF}" "${description}" "{prodList_txt}" "${bandsList_txt}" "${processingTime}"
    # get number of inputs
    inputNum=$#
    # check on number of inputs
    if [ "$inputNum" -ne "5" ]; then
        return ${ERR_PROPERTIES_FILE_CREATOR}
    fi

    # function which creates the .properties file to attach to the output tif file
    local outputProductTif=$1
    local description=$2
    local prodList_txt=$3
    local bandsList_txt=$4
    local processingTime=$5

    outputProductTIF_basename=$(basename "${outputProductTif}")
    properties_filename=${outputProductTif}.properties
    prodList=$( cat ${prodList_txt} )
    bandsList=$( cat ${bandsList_txt}  )

    cat << EOF > ${properties_filename}
title=${outputProductTIF_basename}
description=${description}
processingTime=${processingTime}
${prodList}
${bandsList}
EOF

    [ $? -eq 0 ] && {
        echo "${properties_filename}"
        return 0
    } || return ${ERR_PROPERTIES_FILE_CREATOR}

}


function main ()
{
    #get input product list and convert it into an array
    local -a inputfiles=($@)

    #get the number of products to be processed
    inputfilesNum=$#
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "Number of input products ${inputfilesNum}"
    
    # loop on input products to retrieve them and fill list for stacking operation
    declare -a inputfilesDIM
    declare -a inputProducts
    masterIndex=""
    let "inputfilesNum-=1"
    
    for index in `seq 0 $inputfilesNum`;
    do
        # report activity in log
        ciop-log "INFO" "Retrieving ${inputfiles[$index]} from storage"

        retrieved=$( ciop-copy -U -o $TMPDIR "${inputfiles[$index]}" )
        # check if the file was retrieved, if not exit with the error code $ERR_NODATA
        [ $? -eq 0 ] && [ -e "${retrieved}" ] || return ${ERR_NODATA}

        # report activity in the log
        ciop-log "INFO" "Retrieved ${retrieved}"

        # check if master
        checkMaster=$( ls ${retrieved} | grep .master )
	# if not void is master
	if [ "${checkMaster}" != "" ] ; then
	    # save master index 
            masterIndex=$index 
	    #rename master product removing ".master" extension 
            master_basename_new=$( echo `basename ${retrieved}` | sed 's|.master||g' )
	    mv ${retrieved} ${TMPDIR}/${master_basename_new}
	    retrieved=${TMPDIR}/${master_basename_new}
	fi

	cd $TMPDIR
        tar -xvf `basename ${retrieved}` #&> /dev/null
        # let's check the return value
        [ $? -eq 0 ] || return ${ERR_NODATA}
	# remove tar file 
	rm ${retrieved}
	# get name of uncompressed product in DIM format
        # NOTE: for each loop step, the TMPDIR is cleansd, so the unique product contained is the current one
        inputDIM=$( ls *.dim)
        # move current dim product to input dir
	mv *.d* $INPUTDIR
        # full path of input dim product after move
	inputDIM=${INPUTDIR}/${inputDIM}
        cd - &> /dev/null
        inputfilesDIM+=("${inputDIM}") # Array append       
    done
    
    # data list for stacking
    inputfilesDIM_list=${inputfilesDIM["${masterIndex}"]}
    declare -a bands_list
    # fill band list for master product
    currentBasename=$( basename ${inputfilesDIM["${masterIndex}"]} )
    # extract product name from input name
    # NOTE: it is assumed that the input product is like ${PRODNAME}.${PRODEXT}_pre_proc.dim
    currentBasename="${currentBasename%%.*}"
    # check in case input product is like ${PRODNAME}_pre_proc.dim
    testString=$(echo "${currentBasename}" | grep _pre_proc)
    [ -z "$testString" ] || currentBasename=$(echo $testString | sed -n -e 's|^\(.*\)_pre_proc|\1|p')
    inputProducts+=("${currentBasename}")
    # get band names
    currentBandsList=$( xmlstarlet sel -t -v "/Dimap_Document/Image_Interpretation/Spectral_Band_Info/BAND_NAME" ${inputfilesDIM["${masterIndex}"]} )
    currentBandsList=(${currentBandsList})
    currentBandsList_num=${#currentBandsList[@]}   
    # loop on band names to fill band list    
    let "currentBandsList_num-=1"
    for index in `seq 0 $currentBandsList_num`;
    do
	bands_list+=(${currentBasename}_${currentBandsList[${index}]})	
    done
 
    #loop on input product to fill data list for stacking and band list 
    #the master product has to be the first one so SNAP can use it as Master
    for index in `seq 0 $inputfilesNum`;
    do
        if [ "${index}" -ne "${masterIndex}" ] ; then
            inputfilesDIM_list=${inputfilesDIM_list},${inputfilesDIM[$index]}
            currentBasename=$( basename ${inputfilesDIM["${index}"]} )
	    # extract product name from input name
    	    # NOTE: it is assumed that the input product is like ${PRODNAME}.${PRODEXT}_pre_proc.dim
    	    currentBasename="${currentBasename%%.*}"
            inputProducts+=("${currentBasename}")
    	    # get band names
    	    currentBandsList=$( xmlstarlet sel -t -v "/Dimap_Document/Image_Interpretation/Spectral_Band_Info/BAND_NAME" ${inputfilesDIM[${index}]} )
    	    currentBandsList=(${currentBandsList})
   	    currentBandsList_num=${#currentBandsList[@]}
    	    # loop on band names to fill band list
    	    let "currentBandsList_num-=1"
    	    for index in `seq 0 $currentBandsList_num`;
    	    do
                bands_list+=(${currentBasename}_${currentBandsList["${index}"]})
    	    done
        fi
    done      

    prodList_txt=${TMPDIR}/prodList.txt
    bandsList_txt=${TMPDIR}/bandsList.txt
    # fill products list in txt useful for .properties file creation
    for index in `seq 0 $inputfilesNum`;
    do
        if  [ "${index}" -eq 0 ] ; then
	    echo Master_Product=${inputProducts[$index]} > ${prodList_txt}	   
	else
	    echo Slave_Product_${index}=${inputProducts[$index]} >> ${prodList_txt}
	fi
    done
    # fill bands list in txt useful for .properties file creation
    nBands=${#bands_list[@]}
    let "nBands-=1"
    for index in `seq 0 $nBands`;
    do
	let tmpIndex=$index+1
	if  [ "${index}" -eq 0 ] ; then
	    echo Band_${tmpIndex}=${bands_list[$index]} > ${bandsList_txt}
	else
	    echo Band_${tmpIndex}=${bands_list[$index]} >> ${bandsList_txt}
	fi
    done

    # report activity in the log
    ciop-log "INFO" "Preparing SNAP request file for products stacking"
    # output prodcut name
    outProdTIF=${OUTPUTDIR}/stack_product.tif
    # prepare the SNAP request
    SNAP_REQUEST=$( create_snap_request_stack "${inputfilesDIM_list}" "${outProdTIF}" "${inputfilesNum}" )
    [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
    [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
    # report activity in the log
    ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
    # report activity in the log
    ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for products stacking"
    # invoke the ESA SNAP toolbox
    gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
    # check the exit code
    [ $? -eq 0 ] || return $ERR_SNAP

    # create properties file for phase tif product
    processingTime=$( date )
    description="Multi-missions coregistered product"
    outputTIF_properties=$( propertiesFileCratorTIF  "${outProdTIF}" "${description}" "${prodList_txt}" "${bandsList_txt}" "${processingTime}" )
    # report activity in the log
    ciop-log "DEBUG" "Properties file created: ${outputTIF_properties}"
    cp ${outputTIF_properties} ${OUTPUTDIR}/stack_product.properties
    # publish the coergistered product
    ciop-log "INFO" "Publishing Output Products"
    ciop-publish -m "${OUTPUTDIR}"/* 

    # cleanup
    rm -rf "${INPUTDIR}"/* "${TMPDIR}"/* "${OUTPUTDIR}"/*
    if [ $DEBUG -ne 1 ] ; then
        for index in `seq 0 $inputfilesNum`;
        do
                hadoop dfs -rmr "${inputfiles[$index]}"
        done
    fi

    return ${SUCCESS}
}

# create the output folder to store the output products and export it
mkdir -p ${TMPDIR}/output
export OUTPUTDIR=${TMPDIR}/output
mkdir -p ${TMPDIR}/input
export INPUTDIR=${TMPDIR}/input
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

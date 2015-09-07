#!/bin/bash

RUNJOB_LATEST_VERSION='0.5'

# Kenneth Chan, v0.5 (2015-08-12): adding -a and -V options
# Kenneth Chan, v0.4 (2015-06-30): Allow MEM to be specified using unit
# Kenneth Chan, v0.304001 (2015-06-27): Added config file exist checking
# Kenneth Chan, v0.304 (2015-05-15): Fix a bug for relative OUT_DIR path, added submiting to cluster specific 
# Kenneth Chan, v0.303 (2015-04-27): Fix a bug when no array
# Kenneth Chan, v0.302 (2015-04-16): Fix a bug when the last node is just filled up
# Kenneth Chan, v0.301 (2015-04-16): Added creating the OUT_DIR if needed
# Kenneth Chan, v0.3 (2015-04-16): Fix a bug for no array job submission
# Kenneth Chan, v0.2 (2015-04-14): Added to check for symbolic link
# Kenneth Chan, v0.1 (2015-04-13): To get help, run this script without arguement
# Input file format : Use '-c' option to generate a configFile template
# Copyright statement: Copyright (c) 2015 Applied Bioinformatics Group, UWA, Perth WA, Australia 


##### Default settings
DEBUG=0;
GEN_CONFIG=0;
CHECK_MEM=1;
probeInterval=30;
account='y82';

##### System resources

peTemplate="magnus_run_pe.TEMPLATE"
slurmTemplate="magnus_slurm.TEMPLATE"

MAGNUS_MEM=64G 
MAGNUS_CPU=24

ZEUS_MEM=(
128000
256000
512000
)
ZEUS_CPU=16


cluster='magnus'


##### Handle arguments
usage="\nThis script is a wrapper generating a slurm script to run multiple jobs in magnus.\n"; 
usage="$usage It automatically decides the number of array and jobsPerNode to fully use the resources.\n";
usage="$usage Verion: $RUNJOB_LATEST_VERSION\n\n"
usage="${usage}USAGE: runJobs <configFile>\n";
usage="$usage    -h    This help.\n";
usage="$usage    -d    Debug mode, only generate the submission script but not submit the job.\n";
usage="$usage    -c    Generate a template configFile.\n";
usage="${usage}Advanced options:\n";
usage="$usage    -a    Set the account to be used. Default ${account}.\n";
usage="$usage    -i    Interval of memory probing in job, unit in seconds. Default ${probeInterval}.\n";
usage="$usage    -V    No verbose - disable memory usage checking for jobs.\n";



# The first colon ':' is for disabling the verbose error handling
options=':hdcVi:a:';
while getopts $options OPTION
do
  case $OPTION in
    h) echo -e "$usage"; exit 0;;
    d) DEBUG=1;;
    c) GEN_CONFIG=1;;
    V) CHECK_MEM=0;;
    a) account=$OPTARG;;
    i) probeInterval=$OPTARG;;
		\?) echo;echo "Unknown option -$OPTARG">&2; echo -e $usage; echo; exit 1;;
		:) echo;echo "Missing option argument for -$OPTARG">&2; echo -e $usage; echo; exit 1;;
  esac
done
shift $(( $OPTIND - 1 ));

thisScript="$( which "${0}" )";
if [ -L ${thisScript} ]; then
	thisScript=$( readlink ${thisScript} );
fi
thisScriptDir="$( dirname ${thisScript} )"

# Generate a skeleton template in the current dir
if [ "$GEN_CONFIG" == "1" ]; then
  conf_file="${thisScriptDir}/TEMPLATES/runJobs_config.TEMPLATE";
  if [ -e "${conf_file}" ]; then
    cp "${conf_file}" ./thisJob.conf
    if [ "$?" -ne 0 ]; then
			echo "ERROR in copying the config template to here" 1>&2; exit 1;
    else
      echo "Create a new file thisJob.conf"; exit 0;
    fi
  else
    echo "ERROR: can not find template config file - $conf_file" 1>&2; exit 1;
  fi
fi


# Parse the config file
if [ "${#@}" -ne 1 ]; then
	echo -e $usage; exit 1;
elif [ ! -f "${1}" ]; then 
	echo -e "\nERROR: ${1} does not exist\n$usage"; exit 1;
else
	. ${1}
fi


toByte () {
	VALUE=$1;
	for i in "g G m M k K"; do
		VALUE=${VALUE//[gG]/*1024m}
		VALUE=${VALUE//[mM]/*1024k}
		VALUE=${VALUE//[kK]/*1024}
	done

	[ ${VALUE//\*/} -gt 0 ] && echo $((VALUE)) || echo "ERROR: size invalid, pls enter correct size"
}


# Decide number of jobs per node and number of array required
jobPerNode_mem=$(( `toByte ${MAGNUS_MEM}` / `toByte ${MEM}` ));
jobPerNode_cpu=$(( ${MAGNUS_CPU} / ${CPU} ));
if [ $jobPerNode_mem -le $jobPerNode_cpu ]; then
  jobPerNode=$jobPerNode_mem
else
  jobPerNode=$jobPerNode_cpu
fi

## round up for number of array jobs: (N + (T-1) / T )
arrayJobs=$(( $((${#OPTION_ARG[@]}+$((${jobPerNode}-1)))) / ${jobPerNode} ));   
arrayJobsIndex=$(( ${arrayJobs} - 1 ));   

if [ $DEBUG -eq 1 ]; then
	echo "max jobPerNode: memoryBased $jobPerNode_mem; cpuBased $jobPerNode_cpu"
	echo "final jobPerNode: $jobPerNode; number of array jobs: $arrayJobs; max array index: $arrayJobsIndex";
fi


# create the OUT_DIR if needed
if [ ! -d $OUT_DIR ]; then
	echo "WARNING: OUT_DIR doesn't exist, creating it: mkdir -p $OUT_DIR";
	mkdir -p $OUT_DIR;
fi

# handle the relative OUT_DIR path
if [ "${OUT_DIR:0:1}" == "/" ]; then
	OUT_DIR=$(cd "${OUT_DIR}" && pwd);
else
	OUT_DIR=$(cd "$(dirname ${1})/${OUT_DIR}" && pwd);
fi

resultOut="${OUT_DIR}/jobResults"
if [ ! -d $resultOut ]; then
	mkdir -p $resultOut;
fi
cp ${1} ${OUT_DIR}
thisConfDir="${OUT_DIR}"
thisConfName="$( basename ${1} )"
thisConf="${thisConfDir}/${thisConfName}";



# generate magnus_run_pe.sh from magnus_run_pe.TEMPLATE:
peTemplate="${thisScriptDir}/TEMPLATES/${peTemplate}"
peScript="${OUT_DIR}/magnus_run_pe.sh"

sed -e "s|_CONFIG_FILE_|${thisConf}|" \
    -e "s|_OUT_DIR_|${resultOut}|" \
    -e "s|_PROBE_INTERVAL_|${probeInterval}|" \
		-e "s|_IS_CHECK_MEM_|${CHECK_MEM}|" < ${peTemplate} > ${peScript}


# generate magnus_slurm.slm from magnus_slur.TEMPLATE
slurmTemplate="${thisScriptDir}/TEMPLATES/${slurmTemplate}"
slurmScript="${OUT_DIR}/magnus_slurm.slm"

logOutDir="${resultOut}/slurm_out"
if [ ! -d $logOutDir ]; then
	mkdir -p $logOutDir;
fi


logFileName=${thisConfName%%.*}
logOut="${logOutDir}/${logFileName}_%A.out"
logErr="${logOutDir}/${logFileName}_%A.err"
#cmd="sbatch"
cmd="submitArray.sh"
if [[ "`hostname`" != *${cluster}* ]]
then
	echo "WARNING: Current host is `hostname`, job is submited to ${cluster} specifically"
	cmd="${cmd} -M ${cluster}"
fi
lastArrayNumOfTask=0
if [ $arrayJobsIndex -gt 0 ]; then
	logOut="${logOut}.%a"
	logErr="${logErr}.%a"
	cmd="${cmd} --array=0-${arrayJobsIndex} $slurmScript"
	lastArrayNtasks=$(( ${#OPTION_ARG[@]} % $jobPerNode ))
	if [ $lastArrayNtasks -eq 0 ]; then
		lastArrayNtasks=${jobPerNode}
	fi
else 
	cmd="${cmd} ${slurmScript}"
	jobPerNode=${#OPTION_ARG[@]}
fi

sed -e "s/_JOB_NAME_/${logFileName}/" \
    -e "s|_ACCOUNT_|${account}|" \
    -e "s|_OUTPUT_LOG_|${logOut}|" \
    -e "s|_ERROR_LOG_|${logErr}|" \
    -e "s|_NUM-OF-TASK_|${jobPerNode}|g" \
    -e "s|_HR_|${HOUR}|g" \
    -e "s|_MAX_ARRAY_INDEX_|${arrayJobsIndex}|g" \
    -e "s|_LAST_NTASK_|${lastArrayNtasks}|g" \
    -e "s|_RUN_PE_WRAPPER_|${peScript}|" < ${slurmTemplate} > ${slurmScript}


echo "# submit command: $cmd" >>  ${slurmScript}

# Submit it if not debug
if [ ! -z $DEBUG ] && [ "$DEBUG" -lt 1 ]; then
	echo "RUN: $cmd";
	eval $cmd;
else
	echo "SKIP: $cmd";
fi

exit;


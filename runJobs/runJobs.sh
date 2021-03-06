#!/usr/bin/env bash

RUNJOB_LATEST_VERSION='0.83'

# Kenneth Chan, v0.83 (2016-10-18): Added an optional new config file filename
# Kenneth Chan, v0.82 (2016-04-13): Set default server to the current server, added -q option
# Kenneth Chan, v0.8 (2016-04-11): Generalised the code and added support for raijin
# Kenneth Chan, v0.73001 (2016-01-19): update default group from y82 to pawsey0149
# Kenneth Chan, v0.73 (2015-11-25): added config file checking, and allow OPTION_ARG empty while PROG is not
# Kenneth Chan, v0.72 (2015-11-25): added module to the config file
# Kenneth Chan, v0.71 (2015-11-24): fixed a bug for submitting to zeus when it's not an array job
# Kenneth Chan, v0.7 (2015-11-19): added code to submit jobs to zeus
# Kenneth Chan, v0.6 (2015-09-07): change to use submitArray.sh instead of sbatch
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


thisScript_tmp="$( which "${0}" )";
if [ "$?" -eq "1" ]; then
	thisScript=${0}
elif [ -L ${thisScript_tmp} ]; then
  thisScript=$( readlink ${thisScript_tmp} );
  if [ "${thisScript:0:1}" == "." ]; then
    thisScript="`dirname ${thisScript_tmp}`/${thisScript}";
  fi
else
  thisScript=${thisScript_tmp};
fi
thisScriptDir="$( dirname ${thisScript} )"


if [ ! -f $thisScriptDir/servers.cfg ]; then
	echo "Server config file does not exist: $thisScriptDir/servers.cfg"1>&2; exit 1;
fi
source $thisScriptDir/servers.cfg


##### Default settings

DEBUG=0;
GEN_CONFIG=0;
CHECK_MEM=1;
probeInterval=30;

defaultConfFile='thisJob.conf'

##### System resources


getServerName () {
	thisHost=$HOST
	if [ -z "$thisHost" ]; then
		thisHost=`hostname`
	fi
	if [[ "$thisHost" == zeus* ]]; then 
		echo 'zeus'; 
		return; 
	fi
	if [[ "$thisHost" == raijin* ]]; then 
		echo 'raijin'; 
		return; 
	fi

	# Magnus as the default
	echo 'magnus'; 
}



cluster=`getServerName`


eval account=\$account_$cluster
customiseAccount=0
eval name=\$name_${cluster}



nodetype=''

##### Handle arguments
usage="\nThis script is a wrapper generating a job submission script to run multiple jobs in magnus, zeus and raijin.\n"; 
usage="$usage It automatically decides the number of array and jobsPerNode to fully use the resources.\n";
usage="$usage Version: $RUNJOB_LATEST_VERSION\n\n"
usage="${usage}USAGE: $0 [-h] [-d] [-c [<configFileName>]] [-C <magnus|zeus|raijin>] [-q <nodeType>] [-a <STR>] [-i <INT>] [-V] <configFile>\n";
usage="$usage    -h    This help.\n";
usage="$usage    -d    Debug mode, only generate the submission script but not submit the job.\n";
usage="$usage    -c    Generate a template configFile with the optional config filename. Default name: $defaultConfFile.\n";
usage="${usage}Advanced options:\n";
usage="$usage    -C    Cluster to be run on <magnus|zeus|raijin>. Default current server, eg. ${cluster}\n";
usage="$usage    -q    Node type to be submit to, default magnus:workq; zeus:workq; raijin:normal\n";
usage="$usage    -a    Set the account to be used. Default ${account}.\n";
usage="${usage}Options for pawsey servers:\n";
usage="$usage    -i    Interval of memory probing in job, unit in seconds. Default ${probeInterval}.\n";
usage="$usage    -V    No verbose - disable memory usage checking for jobs.\n";



# The first colon ':' is for disabling the verbose error handling
options=':hdcVi:a:C:q:';
while getopts $options OPTION
do
  case $OPTION in
    h) echo -e "$usage"; exit 0;;
    d) DEBUG=1;;
    c) GEN_CONFIG=1;;
    C) cluster=$OPTARG;;
    q) nodetype=$OPTARG;;
    V) CHECK_MEM=0;;
    a) account=$OPTARG; customiseAccount=1;;
    i) probeInterval=$OPTARG;;
		\?) echo;echo "Unknown option -$OPTARG">&2; echo -e $usage; echo; exit 1;;
		:) echo;echo "Missing option argument for -$OPTARG">&2; echo -e $usage; echo; exit 1;;
  esac
done
shift $(( $OPTIND - 1 ));


# Generate a skeleton template in the current dir
if [ "$GEN_CONFIG" == "1" ]; then
  conf_file="${thisScriptDir}/TEMPLATES/runJobs_config.TEMPLATE";
  if [ -e "${conf_file}" ]; then
		if [ ! -z "$1" ]; then
			defaultConfFile=$1;
		fi

		echo "Create a new config file ${defaultConfFile}";
    cp -i "${conf_file}" $defaultConfFile;
    if [ "$?" -ne 0 ]; then
			echo "ERROR: Couldn't copy the config template to ${defaultConfFile}">&2; exit 1;
    fi
		exit 0;
  else
    echo "ERROR: can not find template config file - $conf_file">&2; exit 1;
  fi
fi


configFileCheck () {
	err=0;
	if [ -z "$CPU" ]; then
		echo "ERROR: CPU in config file is not set.">&2; err=1;
	fi
	if [ -z "$MEM" ]; then
		echo "ERROR: MEM in config file is not set.">&2; err=1;
	fi
	if [ -z "$HOUR" ]; then
		echo "ERROR: HOUR in config file is not set.">&2; err=1;
	fi
	if [ -z "$OUT_DIR" ]; then
		echo "ERROR: OUT_DIR in config file is not set.">&2; err=1;
	fi
	if [ -z "$PROG" ] && [ -z "$OPTION_ARG" ]; then
		echo "ERROR: At least one of PROG or OPTION_ARG in config file needs to be set.">&2; err=1;
	fi

	if [ "$err" -eq 1 ]; then
		exit 1;
	fi
}


# Parse the config file
if [ "${#@}" -ne 1 ]; then
	echo -e $usage; exit 1;
elif [ ! -f "${1}" ]; then 
	echo -e "\nERROR: ${1} does not exist\n$usage"; exit 1;
else
	. ${1}
	configFileCheck
	if [ -z "$OPTION_ARG" ] && [ ! -z "$PROG" ]; then
		echo "OPTION_ARG is empty: $OPTION_ARG"
		echo "PROG is not empty: $PROG"
		OPTION_ARG=( "$PROG" )
		PROG=''
	fi
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


# For calculating values for jobPerNode_mem, jobPerNode_cpu, jobPerNode, arrayJobs and arrayJobsIndex
findJobPerNode () {
	SYS_MEM=$1;
	SYS_CPU=$2;
	# Decide number of jobs per node and number of array required
	jobPerNode_mem=$(( `toByte ${SYS_MEM}` / `toByte ${MEM}` ));
	jobPerNode_cpu=$(( ${SYS_CPU} / ${CPU} ));
	if [ $jobPerNode_mem -le $jobPerNode_cpu ]; then
	  jobPerNode=$jobPerNode_mem
	else
	  jobPerNode=$jobPerNode_cpu
	fi
	
	## round up for number of array jobs: (N + (T-1) / T )
	if [ "${jobPerNode}" -lt 1 ]; then
		# error return
		return 1;
	fi

	arrayJobs=$(( $((${#OPTION_ARG[@]}+$((${jobPerNode}-1)))) / ${jobPerNode} ));   
	arrayJobsIndex=$(( ${arrayJobs} - 1 ));   
	
}



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



eval serverMEM=\$mem_${cluster}
eval serverCPU=\$cpu_${cluster}


for m in ${serverMEM[@]}; do
	findJobPerNode ${m} ${serverCPU[@]};
	if [ "${jobPerNode}" -gt 0 ]; then
		echo "Will use ${cluster} ${m}B node";
		break;
	fi
done


eval cmd=\$submit_${cluster}
if [ "$customiseAccount" == "0" ]; then
	eval account=\$account_${cluster}
fi
eval name=\$name_${cluster}
eval ext=\$ext_${cluster}


if [ "$cluster" == "magnus" ]; then
	submitArrayScript='submitArray.sh'
	which $submitArrayScript &>/dev/null
	if [ "$?" == 0 ]; then
		cmd=$submitArrayScript
	else
		echo "WARNING: $submitArrayScript is not found in PATH, ${cmd} is used instead">&2;
	fi
fi


if [ $DEBUG -eq 1 ]; then
	echo "max jobPerNode: memoryBased $jobPerNode_mem; cpuBased $jobPerNode_cpu"
	echo "final jobPerNode: $jobPerNode; number of array jobs: $arrayJobs; max array index: $arrayJobsIndex";
fi


if [ "$jobPerNode" -lt 1 ]; then
	if [ "${jobPerNode_mem}" -lt "${jobPerNode_cpu}" ]; then
		echo "ERROR: memory request failed - ${cluster} has max ${SYS_MEM}B, you requested ${MEM}B">&2; exit 1;
	else
		echo "ERROR: cpu request failed - ${cluster} has max ${SYS_CPU} cores, you requested ${CPU}">&2; exit 1;
	fi
fi


# generate ${cluster}_run_pe.sh from ${peTemplate}:
peTemplate="${cluster}_run_pe.TEMPLATE"
slurmTemplate="${cluster}_${name}.TEMPLATE"


peTemplate="${thisScriptDir}/TEMPLATES/${peTemplate}"
peScript="${OUT_DIR}/${cluster}_run_pe.sh"

sed -e "s|_CONFIG_FILE_|${thisConf}|" \
    -e "s|_OUT_DIR_|${resultOut}|" \
    -e "s|_PROBE_INTERVAL_|${probeInterval}|" \
		-e "s|_IS_CHECK_MEM_|${CHECK_MEM}|" < ${peTemplate} > ${peScript}

chmod a+x ${peScript}


# generate ${cluster}_${name}.${ext} from ${slurmTemplate}
slurmTemplate="${thisScriptDir}/TEMPLATES/${slurmTemplate}"
slurmScript="${OUT_DIR}/${cluster}_${name}.${ext}"


logOutDir="${resultOut}/${name}_out"
if [ ! -d $logOutDir ]; then
	mkdir -p $logOutDir;
fi


logFileName=${thisConfName%%.*}
logOut="${logOutDir}/${logFileName}.out"
logErr="${logOutDir}/${logFileName}.err"

if [ "${name}" == "slurm" ]; then
	logOut="${logOut}.%A"
	logErr="${logErr}.%A"
fi


if [ "$cluster" != "raijin" ] && [[ "`hostname`" != *${cluster}* ]]
then
	echo "WARNING: Current host is `hostname`, job is submited to ${cluster} specifically"
	cmd="${cmd} -M ${cluster}"
fi


eval array=\$array_${cluster}


if [ $arrayJobsIndex -gt 0 ]; then
	if [ ! -z "${array}" ]; then
		logOut="${logOut}.%a"
		logErr="${logErr}.%a"
		array=`echo $array | sed -e "s/_S_/0/" -e "s/_E_/${arrayJobsIndex}/"`
		cmd="${cmd} ${array}"
	fi

	lastArrayNtasks=$(( ${#OPTION_ARG[@]} % $jobPerNode ))
	if [ $lastArrayNtasks -eq 0 ]; then
		lastArrayNtasks=${jobPerNode}
	fi

else 
	jobPerNode=${#OPTION_ARG[@]}
fi


if [ -z $DEBUG ] || [ "$DEBUG" -ge 1 ]; then
	echo "lastArrayNtasks: $lastArrayNtasks"
fi


if [ ! -z ${MODULES[0]} ]; then
	thisLoadModules='module load'
	for m in ${MODULES[@]}; do
		thisLoadModules="${thisLoadModules} $m"
	done
fi


totalCPU=$(( $jobPerNode * $CPU ))
regex="([0-9]+)([tTgGmMkK])*"
[[ $MEM =~ $regex ]]
memVal=${BASH_REMATCH[1]}
memUnit=${BASH_REMATCH[2]}
totalMEM=$(( $jobPerNode * $memVal ))


if [ -z "$nodetype" ]; then
	eval nodetype=\$nodetype_${cluster}
fi


sed -e "s/_JOB_NAME_/${logFileName}/" \
    -e "s|_ACCOUNT_|${account}|" \
    -e "s|_OUTPUT_LOG_|${logOut}|" \
    -e "s|_ERROR_LOG_|${logErr}|" \
    -e "s|_NUM-OF-TASK_|${jobPerNode}|g" \
    -e "s|_HR_|${HOUR}|g" \
    -e "s|_OMP_CPU_|${CPU}|g" \
    -e "s|_TOTAL-CPU_|${totalCPU}|g" \
    -e "s|_MAX_ARRAY_INDEX_|${arrayJobsIndex}|g" \
    -e "s|_LAST_NTASK_|${lastArrayNtasks}|g" \
    -e "s|_MEM_|${SYS_MEM}|g" \
    -e "s|_TOTAL-MEM_|${totalMEM}${memUnit}|g" \
    -e "s|_MODULES_|${thisLoadModules}|" \
    -e "s|_CUSTOMISE_|${CUSTOMISE}|" \
    -e "s|_NODETYPE_|${nodetype}|" \
    -e "s|_RUN_PE_WRAPPER_|${peScript}|" < ${slurmTemplate} > ${slurmScript}


runJobSupportArray () {
	if [ ! -z $DEBUG ] && [ "$DEBUG" -lt 1 ]; then
		echo "RUN: $cmd";
		eval $cmd;
	else
		echo "SKIP: $cmd";
	fi
}



runJobNotSupportArray () {
	subCmd="$cmd"

	subDir=${slurmScript}_sub
	if [ ! -d ${subDir} ]; then
		mkdir ${subDir};
	fi
	slurmScriptName=`basename ${slurmScript}`;
	for i in `seq 0 ${arrayJobsIndex}`; do

		thisStart=$(( ${i} * ${jobPerNode} ))
		if [ "${arrayJobsIndex}" -eq 0 ] || [ "${i}" -ne ${arrayJobsIndex} ]; then
			thisEnd=$(( ${thisStart} + ${jobPerNode} - 1 ))
		else 
			thisEnd=$(( ${thisStart} + ${lastArrayNtasks} - 1 ))
		fi
		if [ -z $DEBUG ] || [ "$DEBUG" -ge 1 ]; then
			echo "thisStart: ${thisStart}, arrayJobsIndex: ${arrayJobsIndex}, jobPerNode: ${jobPerNode}, lastArrayNtasks: ${lastArrayNtasks}, thisEnd: ${thisEnd}"
		fi
		sed -e "s/_START_/${thisStart}/" -e "s/_END_/${thisEnd}/" ${slurmScript} > ${subDir}/${slurmScriptName}.${i}

		cmd="$subCmd ${subDir}/${slurmScriptName}.${i}"
		echo "# submit command: $cmd" >>  ${subDir}/${slurmScriptName}.${i}
		if [ ! -z $DEBUG ] && [ "$DEBUG" -lt 1 ]; then
			echo "RUN: $cmd";
			eval $cmd;
		else
			echo "SKIP: $cmd";
		fi

	done
}



if [ ! -z "${array}" ]; then
	cmd="$cmd ${slurmScript}"
	echo "# submit command: $cmd" >>  ${slurmScript}
	runJobSupportArray
else
	runJobNotSupportArray
fi


exit;


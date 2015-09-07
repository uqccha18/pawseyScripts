#!/bin/bash -l

# Kenneth Chan, v0.1: Initial Version
# Description: This script is a wrapper to wrap around the sbatch job submission. Automatically do batch submission based on the system config limit.
# Usage: submitArray.sh <jobSubmissionOptions> <jobScript>
# Example: submitArray.sh --array=1-200 mySlurmScript.slm
# Input file format: 
# Output file format: 
# Copyright (c) 2015 Applied Bioinformatics Group, UWA, Perth WA, Australia


#################### Default settings ####################

DEBUG=0

#################### End Default settings ####################


trap 'exit' ERR


usage="\nDescription: This script is a wrapper to wrap around the sbatch job submission. Automatically do batch submission based on the system config limit.\n";
usage="$usage USAGE: bash $0 <jobSubmitssionOptions> <jobScript>\n";
usage="$usage example: bash $0 --array=1-300 mySlurmScript.slm\n";


if [ "$#" == 0 ];then
	echo -e $usage;
	exit 0;
fi


# Get start, end and script
## check if ..../.script_nextRun exist, exist - continue input, not exist - first input
script="${@:$#}";
scriptDir="$( cd "$( dirname "${script}" )" && pwd )";
scriptName=$( basename $script )
scriptNext="${scriptDir}/.${scriptName}_nextRun"
if [ -f ${scriptDir}/.${scriptName}_nextRun ]; then
	start=$( sed -n '1p' $scriptNext )
	end=$( sed -n '2p' $scriptNext )
	otherOptions=$( sed -n '3p' $scriptNext )
	script=$( sed -n '4p' $scriptNext )
else
  # Collect other1, --array/-a, other2, script
  otherOptions=''
  count=0
  for i in $@; do
  	count=$(( $count + 1 ))
  	if [ $# -eq $count ]; then
  		script="${scriptDir}/${scriptName}"
  	elif [[ $i == "--array="* ]] || [[ $i == "-a="* ]]; then
  		if [[ "$i" =~ ^-[-]*a[r]*[r]*[a]*[y]*=([^-]*)-(.*)$ ]]; then
  			start=${BASH_REMATCH[1]}
  			end=${BASH_REMATCH[2]}
  		fi
  	else
  		otherOptions="$otherOptions $i"
  	fi
  done

	if [ -z "$start" ] || [ -z "$end" ]; then
		echo "Not an array job request, submit normally:"
		cmd="sbatch ${otherOptions} ${script}"
		echo $cmd; eval $cmd
		exit $?
	fi
fi



max=`scontrol show config |grep 'MaxArraySize\|MaxTasksPerNode'`
maxArraySize=`echo $max | awk '{print $3-1}'`
# Error if excess limit: end>MaxArraySize, 
if [ $end -gt $maxArraySize ]; then
	echo "ERROR: The requested max array size is greater than the system allowable array size: $maxArraySize">&2; exit 1;
fi

maxTasksPerNode=`echo $max | awk '{print $6}'`


if [ $maxTasksPerNode -gt $maxArraySize ]; then
	maxJobNum=$maxArraySize
else
	maxJobNum=$maxTasksPerNode
fi

numOfJobsInMagnus=$((`squeue -r -u kchan -M magnus -h -o '%i'|wc -l` - 1))

maxAllowJobNum=$(( $maxJobNum - $numOfJobsInMagnus ))



slurmScript="${scriptDir}/.submitArray.slm"

reqNumJob=$(( $end - $start + 1 ))
if [ $reqNumJob -gt $maxAllowJobNum ]; then
	if [ $maxAllowJobNum -gt 1 ]; then
		newEnd=$(( $start + $maxAllowJobNum - 1 ))
		if [ $end -lt $newEnd ]; then
			newEnd=$end
		fi
		cmd="sbatch --array=$start-$newEnd ${otherOptions} $script"
		echo "$cmd";
		jobID=`$cmd`; jobID=${jobID##* };

		# keep a submitted record in .{script}_nextRun
		newStart=$(( $newEnd + 1 ))

		echo -e "${newStart}\n${end}\n${otherOptions}\n${script}" > $scriptNext

		# submit this script: sbatch --dependency=after:${jobID} $thisScript 

		thisScript="$( which "${0}" )";
		if [ -L ${thisScript} ]; then
				thisScript=$( readlink ${thisScript} );
			fi
		thisScriptDir="$( dirname ${thisScript} )"
		slurmTemplate="${thisScriptDir}/TEMPLATES/submitArray.TEMPLATE"

		sed -e "s|_SCRIPT_|$script|" < ${slurmTemplate} > ${slurmScript}
		cmd="sbatch --dependency=after:${jobID} ${slurmScript}"
		echo "$cmd"
		eval $cmd;

	else
		# throw error
		echo "ERROR: Your job queue is full. Consider submitting it again when some of your jobs are finished.">&2; exit 1;
	fi
else
  # direct submission
	cmd="sbatch --array=${start}-${end} ${otherOptions} ${script}"
	echo "$cmd"
	eval $cmd

	if [ -f "$scriptNext" ];then
		rm $scriptNext
	fi
	if [ -f "$slurmScript" ];then
		rm $slurmScript
	fi
fi

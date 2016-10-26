#!/bin/bash -l

# Kenneth Chan, v0.4001: Bug fixed
# Kenneth Chan, v0.4: Handles the max array index limit as well
# Kenneth Chan, v0.2: Fixed bugs - only check hard code kchan queue; check max resource in current node instead of magnus 
# Kenneth Chan, v0.1: Initial Version
# Description: This script is a wrapper to wrap around the sbatch job submission. Automatically do batch submission based on the system config limit.
# Usage: submitArray.sh <jobSubmissionOptions> <jobScript>
# Example: submitArray.sh --array=1-200 mySlurmScript.slm
# Input file format: 
# Output file format: 
# Copyright (c) 2015 Applied Bioinformatics Group, UWA, Perth WA, Australia


trap 'exit' ERR

usage="\nDescription: This script is a wrapper to wrap around the sbatch job submission. Automatically do batch submission based on the system config limit.\n";
usage="$usage USAGE: bash $0 <jobSubmitssionOptions> <jobScript>\n";
usage="$usage example: bash $0 --array=1-300 mySlurmScript.slm\n";


if [ "$#" == 0 ];then
	echo -e $usage;
	exit 0;
fi


# Get start, end and script
## check if ..../.${scriptName}_nextRun exist, exist - continue input, not exist - first input
script="${@:$#}";


scriptDir="$( cd "$( dirname "${script}" )" && pwd )";

scriptName=$( basename $script )
scriptNext="${scriptDir}/.${scriptName}_nextRun"
modScript="${scriptDir}/.${scriptName}_tmp"


if [ -f ${scriptNext} ]; then
	# run the next set when there is some left over jobs
	start=$( sed -n '1p' $scriptNext )
	end=$( sed -n '2p' $scriptNext )
	otherOptions=$( sed -n '3p' $scriptNext )
	script=$( sed -n '4p' $scriptNext )
else
	# Initial run

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

	# handle non-array job
	if [ -z "$start" ] || [ -z "$end" ]; then
		echo "Not an array job request, submit normally:"
		cmd="sbatch ${otherOptions} ${script}"
		echo $cmd; eval $cmd
		exit $?
	fi

fi


# This is an array job and already obtained start, end

# Notify excessing limit: end>MaxArraySize, 
max=`scontrol show config -M magnus |grep 'MaxArraySize\|MaxTasksPerNode'`
maxArraySize=`echo $max | awk '{print $3-1}'`

maxTasksPerNode=`echo $max | awk '{print $6}'`


if [ $maxTasksPerNode -gt $maxArraySize ]; then
	maxJobNum=$maxArraySize
else
	maxJobNum=$maxTasksPerNode
fi

numOfJobsInMagnus=$((`squeue -r -u $USER -M magnus -h -o '%i'|wc -l` - 1))

maxAllowJobNum=$(( $maxJobNum - $numOfJobsInMagnus ))



slurmScript="${scriptDir}/.submitArray.slm"



# When the require number of jobs is equal or less than max allowable job
if [ $maxAllowJobNum -gt 1 ]; then
	newEnd=$(( $start + $maxAllowJobNum - 1 ))
	if [ $end -lt $newEnd ]; then
		newEnd=$end
	fi


	if [ ${start} -ge ${maxArraySize} ] || [ ${newEnd} -ge ${maxArraySize} ]; then

		startArrayBatch=$(( ${start}  / ${maxArraySize} ))
		newEndArrayBatch=$(( ${newEnd}  / ${maxArraySize} ))
		# make sure start and newEnd are in the same array batch
		if [ ${startArrayBatch} != ${newEndArrayBatch} ]; then
			newEnd=$(( ( $maxArraySize * ($startArrayBatch + 1) ) - 1))
		fi

		modStart=$(( ${start} % ${maxArraySize} ))
		modNewEnd=$(( ${newEnd} % ${maxArraySize} ))

		sed -e "s/\$SLURM_ARRAY_TASK_ID/\$((\$SLURM_ARRAY_TASK_ID + ( ${maxArraySize} * ${startArrayBatch} ) ))/g" \
				-e "s/\${SLURM_ARRAY_TASK_ID}/\$((\$SLURM_ARRAY_TASK_ID + ( ${maxArraySize} * ${startArrayBatch} ) ))/g" \
				-e "s/%a/${startArrayBatch}_%a/g" ${script} > ${modScript}

	else
		modStart=$start
		modNewEnd=$newEnd
		modScript="${script}"
	fi


	cmd="sbatch --array=$modStart-$modNewEnd ${otherOptions} $modScript"
	echo "$cmd";
	jobID=`$cmd`; jobID=${jobID##* };


	# keep a submitted record in .{script}_nextRun
	newStart=$(( $newEnd + 1 ))

	if [ $newStart -le $end ]; then
		# if still have some left over, generate the next run required info and submit a monitor job
		echo -e "${newStart}\n${end}\n${otherOptions}\n${script}" > $scriptNext

		# submit this script: sbatch --dependency=after:${jobID} $thisScript 

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


		slurmTemplate="${thisScriptDir}/TEMPLATES/submitArray.TEMPLATE"

		sed -e "s|_SCRIPT_|$script|" < ${slurmTemplate} > ${slurmScript}
		cmd="sbatch --dependency=after:${jobID} ${slurmScript}"
		echo "$cmd"
		eval $cmd;
	else
		# do the clean up
		if [ -f "$scriptNext" ];then
			rm $scriptNext
		fi
		if [ -f "$slurmScript" ];then
			rm $slurmScript
		fi
	fi

else
	# throw error
	echo "ERROR: Your job queue is full. Consider submitting it again when some of your jobs are finished.">&2; exit 1;
fi

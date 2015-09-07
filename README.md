# pawseyScripts
This repository stores some useful pipelines used in Pawsey.

## runJobs
<pre>
This script is a wrapper generating a slurm script to run multiple jobs in magnus.
 It automatically decides the number of array and jobsPerNode to fully use the resources.
 Verion: 0.6

USAGE: runJobs &ltconfigFile&gt
 -h This help.
 -d Debug mode, only generate the submission script but not submit the job.
 -c Generate a template configFile.
 
Advanced options:
 -a Set the account to be used. Default y82.
 -i Interval of memory probing in job, unit in seconds. Default 30.
 -V No verbose - disable memory usage checking for jobs.
</pre>


## submitArray
<pre>
Description: This script is a wrapper to wrap around the sbatch job submission. Automatically do batch submission based on the system config limit.
 USAGE: bash ./submitArray.sh &ltjobSubmitssionOptions&gt &ltjobScript&gt
 example: bash ./submitArray.sh --array=1-300 mySlurmScript.slm
</pre> 


# pawseyScripts
This repository stores some useful pipelines used in Pawsey.

## runJobs
<pre>
This script is a wrapper generating a job submission script to run multiple jobs in magnus, zeus and raijin.
 It automatically decides the number of array and jobsPerNode to fully use the resources.
 Version: 0.83

USAGE: ./runJobs.sh [-h] [-d] [-c [&ltconfigFileName&gt]] [-C &ltmagnus|zeus|raijin&gt] [-q &ltnodeType&gt] [-a &ltSTR&gt] [-i &ltINT&gt] [-V] &ltconfigFile&gt
 -h This help.
 -d Debug mode, only generate the submission script but not submit the job.
 -c Generate a template configFile with the optional config filename. Default name: thisJob.conf.
Advanced options:
 -C Cluster to be run on &ltmagnus|zeus|raijin&gt. Default current server, eg. magnus
 -q Node type to be submit to, default magnus:workq; zeus:workq; raijin:normal
 -a Set the account to be used. Default pawsey0149.
Options for pawsey servers:
 -i Interval of memory probing in job, unit in seconds. Default 30.
 -V No verbose - disable memory usage checking for jobs.
</pre>


## submitArray
<pre>
Description: This script is a wrapper to wrap around the sbatch job submission. Automatically do batch submission based on the system config limit.
 USAGE: bash ./submitArray.sh &ltjobSubmitssionOptions&gt &ltjobScript&gt
 example: bash ./submitArray.sh --array=1-300 mySlurmScript.slm
</pre> 


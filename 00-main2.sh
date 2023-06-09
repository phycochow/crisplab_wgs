#!/bin/bash

#SBATCH --job-name=My_NGS
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=2G
#SBATCH --time=144:00:00
#SBATCH --partition=general
#SBATCH --account=a_crisp

#################################### Setup ########################################
usage="USAGE:
bash 00-main.sh <working_directory>"

working_directory=$1
running_batch_job=1
max_value=0
total_time=0

# Path to the main script
path_to_parameter_sweep_script=/home/s4669612/gitrepos/crisplab_wgs/00-parameter_sweep.sh
path_to_pipeline_script=/home/s4669612/gitrepos/crisplab_wgs/00-pipeline.sh
path_to_subsampling_script=/home/s4669612/gitrepos/crisplab_wgs/00-subsample_fastqgz.sh

# Construct the list of percentages - constant throughout the script
# percentages=(0.01 0.99 0.02 0.98 0.03 0.97 0.04 0.96 0.05 0.95 0.06 0.94 0.07 0.93 0.08 0.92 0.09 0.91 0.10 0.90 0.11 0.89 0.12 0.88 0.13 0.87 0.14 0.86 0.15 0.85 0.16 0.84 0.17 0.83 0.18 0.82 0.19 0.81 0.20 0.80 0.21 0.79 0.22 0.78 0.23 0.77 0.24 0.76 0.25 0.75 0.26 0.74 0.27 0.73 0.28 0.72 0.29 0.71 0.30 0.70 0.31 0.69 0.32 0.68 0.33 0.67 0.34 0.66 0.35 0.65 0.36 0.64 0.37 0.63 0.38 0.62 0.39 0.61 0.40 0.60 0.41 0.59 0.42 0.58 0.43 0.57 0.44 0.56 0.45 0.55 0.46 0.54 0.47 0.53 0.48 0.52 0.49 0.51 0.50)
percentages=(0.01 0.99 0.03 0.97 0.05 0.95 0.07 0.93 0.09 0.91 0.11 0.89 0.13 0.87 0.15 0.85 0.17 0.83 0.19 0.81 0.21 0.79 0.23 0.77 0.25 0.75 0.27 0.73 0.29 0.71 0.30 0.70 0.31 0.69 0.33 0.67 0.35 0.65 0.37 0.63 0.39 0.61 0.41 0.59 0.42 0.58 0.43 0.57 0.45 0.55 0.47 0.53 0.49 0.51 0.50)
no_percentages=${#percentages[@]}

#################################### Run ########################################
# Specify the number of duplicates and the batch size
total_jobs=99
batch_size=5

# Loop through the job array
for ((i=1; i<=total_jobs; i+=batch_size)); do
    batch_jobs=()
    echo "Processing batch: $i to $((i+batch_size-1)), batch_jobs has been reset to ${batch_jobs[@]}"
    
    # Submit jobs for the current batch
    for ((j=i; j<i+batch_size; j++)); do
        if [ $j -le $total_jobs ]; then
            
            # Set index and percentage
            index=$((j % no_percentages))
            percentage=${percentages[$((index-1))]}
            echo "Processing run: $j, Processing percentage: $percentage" 

            # Go/return to parent directory of inputs outputs and processing
            cd "$working_directory"

            # Store and create directories with id number & respective percentage
            fastq_directory="$working_directory"/inputs/reads"$j"_"$percentage"
            processing_directory="$working_directory"/processing"$j"_"$percentage"
            mkdir "$fastq_directory" "$processing_directory"
            mkdir "$processing_directory"/analysis "$processing_directory"/logs

            echo "Submitting subsampling job: $subsampling_job and run_pipeline_job: $run_pipeline_job for run $j"
            subsampling_job=$(sbatch --parsable "$path_to_subsampling_script" "$fastq_directory" "$percentage")
            run_pipeline_job=$(sbatch --parsable --dependency=afterok:$subsampling_job "$path_to_pipeline_script" "$fastq_directory" "$processing_directory" "$percentage")
            
            # Add the running pipeline job to the wait list
            batch_jobs+=("$run_pipeline_job")
            echo "batch_jobs: ${batch_jobs[@]}"
        fi
    done

    # Wait for the current batch to complete
    while [[ $running_batch_job -gt 0 ]]; do # Stops the loop when the no. of running/pending job is no longer greater than 0
        running_batch_job=0
        for job_id in "${batch_jobs[@]}"; do
            condition=$(squeue -h -j "$job_id" -t PD,R | wc -l)
            if [[ $condition -gt 0 ]]; then  # returns True if the no. of running/pending job > 0
                running_batch_job=$((running_batch_job+1))  # If any job is not completed, increment running_batch_job
                echo "$running_batch_job pipline jobs are still running"
            fi
        done
        output=$(/usr/lpp/mmfs/bin/mmlsquota -j S0100 --block-size=auto scratch)
        blocks=$(echo "$output" | awk 'NR>2 {print $3}')
        
        # Special code
        value=$(/usr/lpp/mmfs/bin/mmlsquota -j S0100 --block-size=auto scratch | awk 'NR==3 {sub(/.$/,"",$3); print $3}')
        if [[ $value > $max_value ]]; then
            max_value=$value
        fi
        echo "Data storage peaked at: $max_value GB, total run time for jobs $i to $((j-1)): $total_time" minutes
        ((total_time+=3))
        sleep 180
    done
done


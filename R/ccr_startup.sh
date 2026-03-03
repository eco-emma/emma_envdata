#!/bin/bash


## Script to launch an interactive Apptainer session on CCR

ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
       --job-name=InteractiveJob --nodes=1 --ntasks=4 \
       --mem=10G -C INTEL --time=24:00:00


export GROUP="adamw"
export PROJECT_FOLDER="/projects/academic/"$GROUP
export APPTAINER_CACHEDIR="/vscratch/grp-adamw/"$USER"/singularity"
export SIF_PATH=$PROJECT_FOLDER"/users/"$USER"/singularity"
export SIF_FILE="AdamWilsonLab-emma_docker-latest.sif"

# set singularity cache and tmp directories to the same as apptainer
# needed because CCR is still using singularity and it will use these directories
export SINGULARITY_CACHEDIR=$APPTAINER_CACHEDIR
export SINGULARITY_TMPDIR=$APPTAINER_TMPDIR
export SINGULARITY_LOCALCACHEDIR=$APPTAINER_LOCALCACHEDIR


apptainer run \
      --bind $PROJECT_FOLDER:$PROJECT_FOLDER \
      --bind $APPTAINER_CACHEDIR/tmp:/tmp \
      --bind $APPTAINER_CACHEDIR/run:/run \
      $SIF_PATH/$SIF_FILE R

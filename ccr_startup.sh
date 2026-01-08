#! /bin/bash

# Connect to CCR and request an interactive job

ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
       --job-name=InteractiveJob --nodes=1 --ntasks=4 \
       --mem=10G -C INTEL --time=24:00:00

export GROUP="adamw"
export PROJECT_FOLDER="/projects/academic/"$GROUP
export APPTAINER_CACHEDIR="/vscratch/grp-adamw/"$USER"/singularity"
export SIF_PATH=$PROJECT_FOLDER"/users/"$USER"/singularity"
export SIF_FILE="AdamWilsonLab-emma_docker-latest.sif"


apptainer run \
      --bind $PROJECT_FOLDER:$PROJECT_FOLDER \
      --bind $APPTAINER_CACHEDIR/tmp:/tmp \
      --bind $APPTAINER_CACHEDIR/run:/run \
      $SIF_PATH/$SIF_FILE R       
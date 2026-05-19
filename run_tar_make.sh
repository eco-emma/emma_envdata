#!/bin/bash
# =============================================================================
# Submit with:  sbatch --cluster=faculty run_tar_make.sh
# Monitor with: squeue --cluster=faculty -u $USER
# Cancel with:  scancel --cluster=faculty <JOBID>
# =============================================================================

#SBATCH --cluster=faculty
#SBATCH --qos=adamw
#SBATCH --partition=adamw
#SBATCH --job-name=emma_tar_make
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --mem=250G
#SBATCH -C INTEL
#SBATCH --time=24:00:00
#SBATCH --output=logs/slurm-%j.log
#SBATCH --error=logs/slurm-%j.log
#SBATCH --mail-user=adamw@buffalo.edu
#SBATCH --mail-type=END,FAIL

# =============================================================================
# Paths — edit WORK_DIR if the project moves
# =============================================================================
GROUP="adamw"
WORK_DIR="/projects/academic/${GROUP}/projects/emma/emma_envdata"
PROJECT_FOLDER="/projects/academic/${GROUP}"
APPTAINER_CACHEDIR="/vscratch/grp-adamw/${USER}/singularity"
APPTAINER_TMPDIR="${APPTAINER_CACHEDIR}/tmp"
SIF_PATH="${PROJECT_FOLDER}/users/${USER}/singularity"
SIF_FILE="AdamWilsonLab-emma_docker-latest.sif"

# Singularity legacy variable names (CCR still uses singularity under the hood)
export SINGULARITY_CACHEDIR="${APPTAINER_CACHEDIR}"
export SINGULARITY_TMPDIR="${APPTAINER_TMPDIR}"

# =============================================================================
# Setup
# =============================================================================
mkdir -p "${WORK_DIR}/logs"
mkdir -p "${APPTAINER_CACHEDIR}/tmp"
mkdir -p "${APPTAINER_CACHEDIR}/run"

LOG="${WORK_DIR}/logs/tar_make_${SLURM_JOB_ID}.log"

echo "============================================================" | tee "${LOG}"
echo "Job ID   : ${SLURM_JOB_ID}"                                  | tee -a "${LOG}"
echo "Node     : ${SLURM_NODELIST}"                                 | tee -a "${LOG}"
echo "Started  : $(date)"                                           | tee -a "${LOG}"
echo "Work dir : ${WORK_DIR}"                                       | tee -a "${LOG}"
echo "============================================================" | tee -a "${LOG}"

# =============================================================================
# GitHub token (needed for piggyback uploads to GitHub Releases)
# Prefer GITHUB_PAT (matches .Renviron convention), fall back to GITHUB_TOKEN or gh CLI
# =============================================================================
if [[ -z "${GITHUB_PAT}" ]]; then
  GITHUB_PAT=$(gh auth token 2>/dev/null || echo "")
fi
if [[ -z "${GITHUB_PAT}" ]]; then
  echo "WARNING: GITHUB_PAT not set and 'gh auth token' returned nothing. GitHub uploads will fail." | tee -a "${LOG}"
else
  echo "GITHUB_PAT: set ($(echo "${GITHUB_PAT}" | cut -c1-4)...)" | tee -a "${LOG}"
fi
export GITHUB_PAT

# =============================================================================
# Run tar_make() inside the container
# =============================================================================
apptainer run \
    --bind "${PROJECT_FOLDER}:${PROJECT_FOLDER}" \
    --bind "${APPTAINER_CACHEDIR}/tmp:/tmp" \
    --bind "${APPTAINER_CACHEDIR}/run:/run" \
    --env "GITHUB_PAT=${GITHUB_PAT}" \
    "${SIF_PATH}/${SIF_FILE}" \
    Rscript -e "
      setwd('${WORK_DIR}')
      message('R working directory: ', getwd())
      targets::tar_make()
    " 2>&1 | tee -a "${LOG}"

EXIT_CODE=${PIPESTATUS[0]}

# =============================================================================
# Finish
# =============================================================================
echo "============================================================" | tee -a "${LOG}"
echo "Finished : $(date)"                                           | tee -a "${LOG}"
echo "Exit code: ${EXIT_CODE}"                                      | tee -a "${LOG}"
echo "============================================================" | tee -a "${LOG}"

# Email the log file
SUBJECT="[CCR] emma tar_make ${SLURM_JOB_ID} $([ ${EXIT_CODE} -eq 0 ] && echo 'COMPLETED' || echo 'FAILED')"
mail -s "${SUBJECT}" adamw@buffalo.edu < "${LOG}"

exit ${EXIT_CODE}

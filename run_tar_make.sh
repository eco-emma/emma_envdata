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


# This script is to run targets::tar_make() on the cluster using Apptainer to provide a consistent environment.
  
# =============================================================================
# Paths — edit WORK_DIR if the project moves
# =============================================================================
GROUP="adamw"
WORK_DIR="/projects/academic/${GROUP}/projects/emma/emma_envdata"
PROJECT_FOLDER="/projects/academic/${GROUP}"
export APPTAINER_CACHEDIR="/vscratch/grp-adamw/${USER}/apptainer"
export APPTAINER_TMPDIR="${APPTAINER_CACHEDIR}/tmp"
SIF_PATH="${PROJECT_FOLDER}/users/${USER}/apptainer"
SIF_FILE="AdamWilsonLab-emma_docker-latest.sif"

# Singularity legacy variable names (CCR still uses singularity under the hood)
#export SINGULARITY_CACHEDIR="${APPTAINER_CACHEDIR}"
#export SINGULARITY_TMPDIR="${APPTAINER_TMPDIR}"

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
# Prefer GITHUB_PAT (matches .Renviron convention), fall back to ~/.Renviron, gh CLI
# =============================================================================
if [[ -z "${GITHUB_PAT}" ]]; then
  GITHUB_PAT=$(grep -E "^GITHUB_PAT=" ~/.Renviron 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"'"'"' ')
fi
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
# NASA Earthdata credentials (needed for AppEEARS authentication)
# Read from ~/.Renviron if not already in the environment
# =============================================================================
if [[ -z "${EARTHDATA_USER}" ]]; then
  EARTHDATA_USER=$(grep -E "^EARTHDATA_USER=" ~/.Renviron 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"'"'"' ' | sed 's/[[:space:]]*$//')
fi
if [[ -z "${EARTHDATA_PASSWORD}" ]]; then
  EARTHDATA_PASSWORD=$(grep -E "^EARTHDATA_PASSWORD=" ~/.Renviron 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"'"'"' ' | sed 's/[[:space:]]*$//')
fi
if [[ -z "${EARTHDATA_USER}" || -z "${EARTHDATA_PASSWORD}" ]]; then
  echo "WARNING: EARTHDATA_USER or EARTHDATA_PASSWORD not set. AppEEARS authentication will fail." | tee -a "${LOG}"
else
  echo "EARTHDATA_USER: ${EARTHDATA_USER}" | tee -a "${LOG}"
fi
export EARTHDATA_USER
export EARTHDATA_PASSWORD

# =============================================================================
# Run tar_make() inside the container
# =============================================================================
# Write credentials to a temp env-file using printf '%s' (no shell expansion),
# so passwords containing '$', '!', or backticks are passed verbatim.
APPTAINER_ENV_FILE=$(mktemp)
chmod 600 "${APPTAINER_ENV_FILE}"
trap 'rm -f "${APPTAINER_ENV_FILE}"' EXIT
printf 'GITHUB_PAT=%s\n'          "${GITHUB_PAT}"          >> "${APPTAINER_ENV_FILE}"
printf 'EARTHDATA_USER=%s\n'      "${EARTHDATA_USER}"      >> "${APPTAINER_ENV_FILE}"
printf 'EARTHDATA_PASSWORD=%s\n'  "${EARTHDATA_PASSWORD}"  >> "${APPTAINER_ENV_FILE}"

apptainer run \
    --bind "${PROJECT_FOLDER}:${PROJECT_FOLDER}" \
    --bind "${APPTAINER_CACHEDIR}/tmp:/tmp" \
    --bind "${APPTAINER_CACHEDIR}/run:/run" \
    --env-file "${APPTAINER_ENV_FILE}" \
    --env TMPDIR=/tmp \
    "${SIF_PATH}/${SIF_FILE}" \
    Rscript -e "
      setwd('${WORK_DIR}')
      message('R working directory: ', getwd())
      targets::tar_make()
    " 2>&1 | tee -a "${LOG}"

EXIT_CODE=${PIPESTATUS[0]}

# =============================================================================
# Upload targets cache to GitHub release (runs even on partial tar_make failure
# so that completed targets are cached for the next run)
# =============================================================================
echo "============================================================" | tee -a "${LOG}"
echo "Uploading targets cache to GitHub release..."                 | tee -a "${LOG}"
echo "Started  : $(date)"                                           | tee -a "${LOG}"
echo "============================================================" | tee -a "${LOG}"

apptainer run \
    --bind "${PROJECT_FOLDER}:${PROJECT_FOLDER}" \
    --bind "${APPTAINER_CACHEDIR}/tmp:/tmp" \
    --bind "${APPTAINER_CACHEDIR}/run:/run" \
    --env-file "${APPTAINER_ENV_FILE}" \
    "${SIF_PATH}/${SIF_FILE}" \
    Rscript -e "
      setwd('${WORK_DIR}')
      library(targets)
      source('R/tar_release_storage.R')
      tar_upload_github_release(
        repo      = 'AdamWilsonLab/emma_envdata',
        tag       = 'targets-cache',
        cache_dir = '_targets/cache',
        verbose   = TRUE
      )
    " 2>&1 | tee -a "${LOG}"

UPLOAD_EXIT_CODE=${PIPESTATUS[0]}

# =============================================================================
# Finish
# =============================================================================
echo "============================================================" | tee -a "${LOG}"
echo "Finished      : $(date)"                                      | tee -a "${LOG}"
echo "tar_make exit : ${EXIT_CODE}"                                 | tee -a "${LOG}"
echo "upload exit   : ${UPLOAD_EXIT_CODE}"                          | tee -a "${LOG}"
echo "============================================================" | tee -a "${LOG}"

exit ${EXIT_CODE}

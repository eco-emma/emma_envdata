#!/bin/bash
# =============================================================================
# One-time migration to split STAC and MODIS VI GitHub releases.
# Submitted via sbatch (not run interactively) because interactive salloc
# nodes on this cluster may lack outbound DNS/internet access to GitHub,
# while sbatch --cluster=faculty jobs land on nodes that have it (same
# pattern used by run_tar_make.sh for its upload step).
#
# Submit with:  sbatch --cluster=faculty run_backfill_stac.sh
# Monitor with: squeue --cluster=faculty -u $USER
# =============================================================================

#SBATCH --cluster=faculty
#SBATCH --qos=adamw
#SBATCH --partition=adamw
#SBATCH --job-name=emma_backfill_stac
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --output=logs/backfill_stac-%j.log
#SBATCH --error=logs/backfill_stac-%j.log
#SBATCH --mail-user=adamw@buffalo.edu
#SBATCH --mail-type=END,FAIL

GROUP="adamw"
WORK_DIR="/projects/academic/${GROUP}/projects/emma/emma_envdata"
PROJECT_FOLDER="/projects/academic/${GROUP}"
export APPTAINER_CACHEDIR="/vscratch/grp-adamw/${USER}/apptainer"
export APPTAINER_TMPDIR="${APPTAINER_CACHEDIR}/tmp"
SIF_PATH="${PROJECT_FOLDER}/users/${USER}/apptainer"
SIF_FILE="AdamWilsonLab-emma_docker-latest.sif"

export APPTAINER_LOCALCACHEDIR="${APPTAINER_CACHEDIR}/localcache"
export SINGULARITY_LOCALCACHEDIR="${APPTAINER_LOCALCACHEDIR}"

mkdir -p "${WORK_DIR}/logs"
mkdir -p "${APPTAINER_CACHEDIR}/tmp"

LOG="${WORK_DIR}/logs/backfill_stac_${SLURM_JOB_ID}.log"

echo "============================================================" | tee "${LOG}"
echo "Job ID   : ${SLURM_JOB_ID}"                                  | tee -a "${LOG}"
echo "Node     : ${SLURM_NODELIST}"                                 | tee -a "${LOG}"
echo "Started  : $(date)"                                           | tee -a "${LOG}"
echo "============================================================" | tee -a "${LOG}"

# GitHub token (needed for uploads to GitHub Releases)
if [[ -z "${GITHUB_PAT}" ]]; then
  GITHUB_PAT=$(grep -E "^GITHUB_PAT=" ~/.Renviron 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"'"'"' ')
fi
if [[ -z "${GITHUB_PAT}" ]]; then
  GITHUB_PAT=$(gh auth token 2>/dev/null || echo "")
fi
if [[ -z "${GITHUB_PAT}" ]]; then
  echo "WARNING: GITHUB_PAT not set and 'gh auth token' returned nothing. Uploads will fail." | tee -a "${LOG}"
else
  echo "GITHUB_PAT: set ($(echo "${GITHUB_PAT}" | cut -c1-4)...)" | tee -a "${LOG}"
fi
export GITHUB_PAT

APPTAINER_ENV_FILE=$(mktemp)
chmod 600 "${APPTAINER_ENV_FILE}"
trap 'rm -f "${APPTAINER_ENV_FILE}"' EXIT
printf 'GITHUB_PAT=%s\n' "${GITHUB_PAT}" >> "${APPTAINER_ENV_FILE}"

apptainer run \
    --bind "${PROJECT_FOLDER}:${PROJECT_FOLDER}" \
    --bind "${APPTAINER_TMPDIR}:/tmp" \
    --env-file "${APPTAINER_ENV_FILE}" \
    --env TMPDIR=/tmp \
    "${SIF_PATH}/${SIF_FILE}" \
    Rscript -e "
      setwd('${WORK_DIR}')
      message('R working directory: ', getwd())
      source('R/backfill_stac_release.R')
    " 2>&1 | tee -a "${LOG}"

EXIT_CODE=${PIPESTATUS[0]}

echo "============================================================" | tee -a "${LOG}"
echo "Finished      : $(date)"                                      | tee -a "${LOG}"
echo "backfill exit : ${EXIT_CODE}"                                 | tee -a "${LOG}"
echo "============================================================" | tee -a "${LOG}"

exit ${EXIT_CODE}

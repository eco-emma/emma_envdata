#!/usr/bin/env bash
# =============================================================================
# Interactive Apptainer launcher for CCR
#
# 1. From your laptop, SSH to CCR:
#      ssh vortex.ccr.buffalo.edu
# 2. On CCR, request an interactive node:
#      salloc --cluster=faculty --qos=adamw --partition=adamw \
#        --job-name=emma_interactive --nodes=1 --ntasks=4 --mem=24G \
#        -C INTEL --time=24:00:00
# 3. On the allocated node, run one of:
#      bash R/ccr_startup.sh rstudio
#      bash R/ccr_startup.sh R
#      bash R/ccr_startup.sh shell
# =============================================================================

set -euo pipefail

MODE="${1:-shell}"
GROUP="${GROUP:-adamw}"
LOGIN_HOST="${LOGIN_HOST:-vortex.ccr.buffalo.edu}"
PORT="${PORT:-8787}"
WORK_DIR="${WORK_DIR:-/projects/academic/${GROUP}/projects/emma/emma_envdata}"
PROJECT_FOLDER="${PROJECT_FOLDER:-/projects/academic/${GROUP}}"

export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-/vscratch/grp-${GROUP}/${USER}/apptainer}"
export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-${APPTAINER_CACHEDIR}/tmp}"
export APPTAINER_LOCALCACHEDIR="${APPTAINER_LOCALCACHEDIR:-${APPTAINER_CACHEDIR}/localcache}"
export SINGULARITY_CACHEDIR="${SINGULARITY_CACHEDIR:-${APPTAINER_CACHEDIR}}"
export SINGULARITY_TMPDIR="${SINGULARITY_TMPDIR:-${APPTAINER_TMPDIR}}"
export SINGULARITY_LOCALCACHEDIR="${SINGULARITY_LOCALCACHEDIR:-${APPTAINER_LOCALCACHEDIR}}"

SIF_PATH="${SIF_PATH:-${PROJECT_FOLDER}/users/${USER}/apptainer}"
SIF_FILE="${SIF_FILE:-AdamWilsonLab-emma_docker-latest.sif}"
SIF="${SIF_PATH}/${SIF_FILE}"
NODE_HOST="$(hostname -f 2>/dev/null || hostname)"

mkdir -p \
       "${APPTAINER_TMPDIR}" \
       "${APPTAINER_CACHEDIR}/run" \
       "${APPTAINER_CACHEDIR}/rstudio-server" \
       "${APPTAINER_LOCALCACHEDIR}"

if [[ ! -f "${SIF}" ]]; then
       echo "Missing Apptainer image: ${SIF}" >&2
       echo "Create it with:" >&2
       echo "  mkdir -p '${SIF_PATH}'" >&2
       echo "  apptainer pull '${SIF}' docker://adamwilsonlab/emma:latest" >&2
       exit 1
fi

common_args=(
       --bind "${PROJECT_FOLDER}:${PROJECT_FOLDER}"
       --bind "${APPTAINER_TMPDIR}:/tmp"
       --bind "${APPTAINER_CACHEDIR}/run:/run"
       --env "TMPDIR=/tmp"
)

case "${MODE}" in
       rstudio)
              echo "Start this tunnel from your laptop, then open http://localhost:${PORT}:"
              echo "  ssh -N -L ${PORT}:${NODE_HOST}:${PORT} ${LOGIN_HOST}"
              echo
              cd "${WORK_DIR}"
              exec apptainer exec "${common_args[@]}" "${SIF}" \
                     rserver \
                            --www-address=0.0.0.0 \
                            --www-port="${PORT}" \
                            --auth-none=1 \
                            --server-user="${USER}" \
                            --server-data-dir="${APPTAINER_CACHEDIR}/rstudio-server" \
                            --server-working-dir="${WORK_DIR}"
              ;;
       R)
              cd "${WORK_DIR}"
              exec apptainer run "${common_args[@]}" "${SIF}" R --no-save --no-restore
              ;;
       shell|bash)
              cd "${WORK_DIR}"
              exec apptainer shell "${common_args[@]}" "${SIF}"
              ;;
       *)
              echo "Usage: bash R/ccr_startup.sh [rstudio|R|shell]" >&2
              exit 2
              ;;
esac

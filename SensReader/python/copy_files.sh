#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=192   
#SBATCH --time=0-00:15:00
#SBATCH --mem=128GB
#SBATCH --job-name=openmp_job
#SBATCH --output=%N-copy_files-multi-%j.out
#SBATCH --mail-type=FAIL

# Use rsync with --info=progress2 for progress, and -a for archive mode.
# GNU parallel is used to parallelize across 192 CPU cores, splitting the scenes.
SRC="/project/def-wangcs/indrisch/vllm/data/ScanNet/scans"
DST="/scratch/indrisch/scans"

# Make sure destination directory exists
mkdir -p "$DST"

# Export variables for GNU parallel
export SRC DST

# Find (top level) scene directories, then rsync them in parallel. This ensures safe parallel copy.
find "$SRC" -mindepth 1 -maxdepth 1 -type d | parallel -j 192 rsync -a --info=progress2 {} "$DST"/

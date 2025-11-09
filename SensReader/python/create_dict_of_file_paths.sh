#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8   
#SBATCH --time=0-00:15:00
#SBATCH --job-name=openmp_job
#SBATCH --output=%N-create_dict_of_file_paths-multi-%j.out
#SBATCH --mail-type=FAIL

# run as: sbatch ./create_dict_of_file_paths.sh <cluster_name> <experiment> [sub-experiment-1] [sub-experiment-2]
# runs in 4 minutes 30 seconds without enforcing eager and flashinfer.

# with 13 chunks, it takes about 2 hours to get 550 out of 650 scenes. 

module load StdEnv/2023
module load gcc/12.3
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

if [[ $# -gt 4 || $# -lt 2 ]]; then
    echo "Usage: $0 <cluster_name> <experiment> [sub-experiment-1] [sub-experiment-2]"
    exit 1
fi

export CLUSTER_NAME=$1
export EXPERIMENT=$2
export SUB_EXPERIMENT_1=$3
export SUB_EXPERIMENT_2=$4

if [[ "$PWD" == *vllm_experiments* ]]; then
    PROJECT_DIR="${PWD%%vllm_experiments*}/vllm_experiments"
elif [[ "$PWD" == *vllm* ]]; then
    PROJECT_DIR="${PWD%%vllm*}/vllm"
else
    echo "Error: Could not find 'vllm' or 'vllm_experiments' in the current path."
    exit 1
fi
SYSCONFIG_DIR_PATH="$PROJECT_DIR/kimi_vl_a3b_thinking_2506/kimivl_3d_test"
export PYTHONPATH="$PYTHONPATH:$SYSCONFIG_DIR_PATH"

MODEL="Qwen/Qwen3-4B-Thinking-2507"
SCENES="/scratch/indrisch/vllm_experiments/data/ScanNet/scans"
EXP_DIR="/scratch/indrisch/vllm_experiments/data_support/ScanNet/SensReader/python"
ANNO_DIR="${PROJECT_DIR}/data/sqa-3d/ScanQA_format"

source /scratch/indrisch/env/bin/activate

export HF_HOME="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'HF_HOME'))")"
export HF_HUB_CACHE="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'HF_HUB_CACHE'))")"
export HF_HUB_DISABLE_XET="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'HF_HUB_DISABLE_XET'))")"
export HF_HUB_OFFLINE="1"
export TRITON_CACHE_DIR="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'TRITON_CACHE_DIR'))")"
export VLLM_CONFIG_DIR="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'VLLM_CONFIG_DIR'))")"
export VLLM_CONFIG_ROOT="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'VLLM_CONFIG_ROOT'))")"
export VLLM_CACHE_ROOT="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'VLLM_CACHE_ROOT'))")"
export BEST_GPU="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'BEST_GPU'))")"
export FLASHINFER_WORKSPACE_BASE="$(python3 -c "import sysconfigtool; print(sysconfigtool.read('$CLUSTER_NAME', 'FLASHINFER_WORKSPACE_BASE'))")"

if [[ "$BEST_GPU" == "h100" ]]; then
    export TORCH_CUDA_ARCH_LIST="9.0"
else
    export TORCH_CUDA_ARCH_LIST="8.0"
fi

if [ $BEST_GPU == "a100" ]; then
    export TENSOR_PARALLEL_SIZE=2
else
    export TENSOR_PARALLEL_SIZE=1
fi


#python /scratch/indrisch/vllm_experiments/correctness/cpu-correctness.py --cluster_name $CLUSTER_NAME
echo PYTHONPATH: $PYTHONPATH
#"${PROJECT_DIR}/correctness/experiment_runner.sh" "${CLUSTER_NAME}" "${EXPERIMENT}" "${SUB_EXPERIMENT_1}" "${SUB_EXPERIMENT_2}"
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export VLLM_LOGGING_LEVEL=DEBUG

echo "Running trace_combiner.py"

chunk=$(expr $SUB_EXPERIMENT_1 - 1)
python create_dict_of_file_paths.py \
            --question_file ${ANNO_DIR}/SQA_650_formatted_LLaVa3d_annotations.json \
            --answer_file ${ANNO_DIR}/SQA_650_formatted_LLaVa3d_answers.json \
            --image_folder ${SCENES} \
            --export_json /scratch/indrisch/vllm_experiments/data_support/ScanNet/SensReader/python/SQA3D_dataset_details_noslurm_trillium_1of1.json \
            --cluster_name ${CLUSTER_NAME} \
            --traces_json ${PROJECT_DIR}/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers.json \
            --model_path ${MODEL} \
            --device cpu \
            --sample_rate 15 \
            --batch_size -1 \
            --num_chunks ${SUB_EXPERIMENT_2} \
            --chunk_idx $chunk \
            --tensor_parallel_size ${TENSOR_PARALLEL_SIZE}

import json
from math import comb
from natsort import natsorted
import os

def remove_duplicates(traces: list):
    """
    Remove duplicates from a list of traces.
    """
    num_traces = len(traces)
    i = 0
    while i < num_traces - 2:
        if traces[i]["question_id"] == traces[i+1]["question_id"]:
            print(f"Removing duplicate question_id: {traces[i]['question_id']} at index {i}")
            traces.pop(i)
            num_traces -= 1
        i += 1
    return traces


def combine_traces(trace_files: list, output_file: str):
    """
    Combine multiple trace files into a single file.
    """
    traces = []
    for trace_file in trace_files:
        with open(trace_file, "r") as f:
            traces.extend(json.load(f))
        f.close()
    traces = natsorted(traces, key=lambda x: x["question_id"])
    traces = remove_duplicates(traces)
    with open(output_file, "w") as f:
        json.dump(traces, f, indent=4)
    f.close()


if __name__ == "__main__":
    # trace_files = ["/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk1of30-partial.json", 
    #                "/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk7of360.json",
    #                "/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk8of360.json",
    #                "/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk9of360.json",
    #                "/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk10of360.json",
    #                "/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk11of360.json",
    #                "/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk12of360.json"]
    # combine_traces(trace_files, "/project/def-wangcs/indrisch//vllm/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk1of30.json")
    # trace_files = ["/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk22of30-partial.json",
    #                "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk270of360.json",
    #                "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk271of360.json",
    #                "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk272of360.json",
    #                "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk273of360.json",
    #                "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk274of360.json",
    #                "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk275of360.json",
    #                "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk276of360.json"]
    # combine_traces(trace_files, "/home/indrisch/projects/def-wangcs/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk22of30.json")
    # trace_files = [f'/scratch/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers-chunk{i}of30.json' for i in range(1, 31)]
    # combine_traces(trace_files, "/scratch/indrisch/vllm_experiments/kimi_vl_a3b_thinking_2506/kimivl_3d_test/experiments/SQA3D/650/SQA_650_formatted_LLaVa3d_pred-answers.json")
    files = os.listdir("/scratch/indrisch/vllm_experiments/data_support/ScanNet/SensReader/python/")
    traces = []
    for f in files:
        if f.endswith("13.json") or f.endswith("130.json") or f.endswith("noslurm_1of1.json"):
            with open(f, "r") as f:
                traces.extend(json.load(f))
            f.close()
            
    traces = [d for d in traces if isinstance(d, dict)]
    
    checklist = []
    for t in traces:
        if t["scene"] not in checklist:
            checklist.append(t["scene"])
        else:
            print(f"Duplicate scene: {t['scene']}")
            # remove the duplicate
            traces.remove(t)
        
    json.dump(traces, open("/scratch/indrisch/vllm_experiments/data_support/ScanNet/SensReader/python/SQA3D_dataset_details_noslurm_trillium_1of1.json", "w"), indent=4)
    
    scenes_found = list(set([t["scene"] for t in traces]))
    
    # read the contents of /scratch/indrisch/vllm_experiments/data/sqa-3d/ScanQA_format/the_650_scenes.txt into a list
    with open("/scratch/indrisch/vllm_experiments/data/sqa-3d/ScanQA_format/the_650_scenes.txt", "r") as f:
        scenes_all = f.read().splitlines()
    f.close()

    scenes_missing = [scene for scene in scenes_all if scene not in scenes_found]

    print(f"Number of scenes found: {len(scenes_found)}")
    print(f"Number of scenes missing: {len(scenes_missing)}")
    print(f"Scenes missing: {scenes_missing}")

    # write the scenes_missing to a file
    with open("scenes_missing.txt", "w") as f:
        for scene in scenes_missing:
            f.write(f"{scene}\n")
    f.close()
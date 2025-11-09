import multiprocessing

import sys, os
import argparse
import math
import json
from natsort import natsorted
from operator import itemgetter
import gc
import time
import re
import math
from typing import Union, Tuple, Optional
import subprocess

def split_list(lst, n):
    """Split a list into n (roughly) equal-sized chunks"""
    chunk_size = math.ceil(len(lst) / n)  # integer division
    return [lst[i:i+chunk_size] for i in range(0, len(lst), chunk_size)]


def get_chunk(lst, n, k):
    chunks = split_list(lst, n)
    return chunks[k]

def dars_to_folders(image_folder_path: str, scene_name: str):
    """
    """
    color_dir_option1 = os.path.join(image_folder_path, scene_name, scene_name + "_sens", "color")
    color_dir_option2 = os.path.join(image_folder_path, scene_name, "color")
    if os.path.isdir(color_dir_option1) or os.path.isdir(color_dir_option2):
        print(f"Color directory already exists for scene {scene_name}.")
    else:
        try:
            head = os.getcwd()[:os.getcwd().index("vllm_experiments")] + "/vllm_experiments/"
        except ValueError:
            head = os.getcwd()[:os.getcwd().index("vllm")] + "/vllm/"
        create_dars_script = subprocess.run(["find", head, "-name", "create_dars.sh"], capture_output=True, text=True).stdout[:-1]
        dars_command = create_dars_script + " " + scene_name + " --dars_to_folders --num_workers 4 --export_color_images"
        print("running: ", dars_command)
        os.system(dars_command)


def delete_folders(scene_name: str):
    """
    """
    try:
        head = os.getcwd()[:os.getcwd().index("vllm_experiments")] + "/vllm_experiments/"
    except ValueError:
        head = os.getcwd()[:os.getcwd().index("vllm")] + "/vllm/"
    create_dars_script = subprocess.run(["find", head, "-name", "create_dars.sh"], capture_output=True, text=True).stdout[:-1]
    dars_command = create_dars_script + " " + scene_name + " --delete_folders --num_workers 4 --export_color_images"
    print("running: ", dars_command)
    os.system(dars_command)


def load_traces_json(file_path: str, sort_by_scene: bool = False):
    """
    Load traces from a JSON file.
    Args:
        file_path (str): Path to the JSON file.
    Returns:
        list: List of traces.
    """
    with open(file_path, "r") as f:
        traces = json.load(f)
    f.close()
    print("Number of traces in the file: ", len(traces))
    if sort_by_scene:
        traces = natsorted(traces, key=itemgetter("video"))
    return traces


def add_answers_to_traces(traces: list, answer_file: str, num_chunks: int, chunk_idx: int):
    """
    Add answers to traces by matching question_id.
    Args:
        traces (list): List of traces.
        answer_file (str): Path to the answer JSON file.
    Returns:
        list: List of traces with answers.
    """
    with open(answer_file, "r") as f:
        answers = json.load(f)
        #answers = get_chunk(answers, num_chunks, chunk_idx)
        #answers = answers # [answers[0]] # [:]  # [:] to control how many get used, e.g. [answers[0]] for only the first answer. If we want answers to agree, we can add to a new "answers" in "if qid in answer_lookup"
    f.close()
        
    # Build a lookup dict for answers by question_id
    answer_lookup = {a["question_id"]: a for a in answers}
    for trace in traces:
        qid = trace["question_id"]
        if qid in answer_lookup:
            trace["ground_truth_answer"] = answer_lookup[qid]["text"]
            trace["type"] = answer_lookup[qid]["type"]
        else:
            trace["ground_truth_answer"] = None
            trace["type"] = None
    return traces


def get_existing_scenes(overwrite_existing_json: bool, export_json_path: str):
    if overwrite_existing_json and os.path.exists(export_json_path):
        os.remove(export_json_path)
    
    try:
        with open(export_json_path, "r") as f:
            traces = json.load(f)
        f.close()
    except FileNotFoundError:
        traces = []
    return traces


def extract_list_of_traces(trace: dict):
    """
    Extract the list of traces from the trace.
    Args:
        trace (dict): A dict with keys "0", "1", ..., "n-1", these are the n traces. "best_trace_index" and "best_trace" may also be present, ignore these.
    Returns:
        list: List of the values of the keys "0", "1", ..., "n-1".
    """
    trace_numeric_keys = {}
    for key in trace.keys():
        try:
            trace_numeric_keys[int(key)] = trace[key]
        except ValueError:
            continue
    trace_list = [None] * len(trace_numeric_keys)
    for key, value in trace_numeric_keys.items():
        trace_list[key] = value
    return trace_list


def save_output_json(output_dict: dict, output_file_path: str):
    """
    Save the model's output to a file.
    Args:
        output_dict (dict): trace results
        output_file_path (str): Path to save the output
    """
    # get a list of the existing traces; if no traces yet, make an empty list.
    try:
        with open(output_file_path, "r") as f:
            traces = json.load(f)
        f.close()
    except FileNotFoundError:
        traces = []
        
    # add the new trace to the list
    traces.append(output_dict)
    
    # Save to file
    with open(output_file_path, "w") as f:
        json.dump(traces, f, indent=4)
    f.close()


def normalize_answer(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower())


def extract_final_answer(pred: str, gt: str) -> float:
    f"""
    Provides a final score based on the correctness of the predicted answer.
    - if the gt appears somewhere in the pred, the score is 0.5
    - if the gt appears in the pred in a way that makes it seem like that is the model's final decision, the score is increased by 0.5 to 1.0. The following cases would earn this extra 0.5:
        - the pred ends with the gt (i.e. is followed by nothing, punctuation or a newline)
        - the substrings "\\boxed{gt}" or "**gt**" appear anywhere in the pred
    - otherwise, the score is 0.0
    
    
    Args:
        pred (str): A trace (sentence, with thinking and final answer) that is a model's train of thought while they try to answer a question (and try to arrive at the ground truth answer)
        gt (str): The ground truth answer.
    Returns:
        float: The correctness score.
    """
    score = 0.0
    # check if the gt appears somewhere in the pred
    if gt in pred:
        score = 0.5
        # check if the gt appears in the pred in a way that makes it seem like that is the model's final decision, using regex
        pos = pred.rfind(gt)
        suffix = pred[pos + len(gt):] if pos != -1 else ""
        if len(suffix) == 0 or re.fullmatch(r"(?:!|\.|\n)", suffix) or "\boxed{" + gt + "}" in pred or "**" + gt + "**" in pred:
            score = 1.0
    return score


def correctness_scores_by_trace(num_traces: int, traces: dict) -> float:
    """
    Calculate the correctness scores for each trace.
    Args:
        traces (dict): A dict with keys "question_id", "video", "question", "ground_truth_answer", "answer".
    Returns:
        list: A list of length <number_of_traces> with the correctness scores for each trace.
    """
    # trace = trace["answer"]["0"]
    # trace.replace("--------Thinking--------", "")
    # trace.replace("--------Summary--------", "")
    # trace.replace("MISSING: EOT", "")
    # trace.replace("MISSING: BOT", "")
    # trace.replace("MISSING: BOT AND EOT", "")
    correctness_scores = [0.0] * num_traces
    for trace_idx in range(num_traces):
        trace = traces["answer"][str(trace_idx)]
        trace = normalize_answer(trace)
        gt = normalize_answer(traces["ground_truth_answer"])
        correctness_scores[trace_idx] = extract_final_answer(trace, gt)
    return correctness_scores


def _worker_run(worker_id, args, results):
    """
    Run one chunk in a separate process and store outputs in results[worker_id].
    """
    outputs = main(
        cluster_name=args.cluster_name,
        question_file_path=args.question_file,
        answer_file_path=args.answer_file,
        traces_json_path=args.traces_json,
        image_folder_path=args.image_folder,
        export_json_path=args.export_json,
        model_path=args.model_path,
        num_chunks=args.num_chunks,
        chunk_idx=worker_id,
        mc_traces=args.mc_traces,
        batch_size=args.batch_size,
        device=args.device,
        sample_rate=args.sample_rate,
        overwrite_existing_json=False,  # parent handles overwrite once
        sort_by_scene=args.sort_by_scene,
        tensor_parallel_size=args.tensor_parallel_size
    )
    results[worker_id] = outputs


def main(
    cluster_name: str,
    question_file_path: str,
    answer_file_path: str,
    traces_json_path: str,
    image_folder_path: str,
    export_json_path: str,
    model_path: str,
    num_chunks: int,
    chunk_idx: int,
    mc_traces: int,
    batch_size: int,
    device: str = "cpu",
    sample_rate: int = 5,
    overwrite_existing_json: bool = False,
    sort_by_scene: bool = False,
    tensor_parallel_size: int = 1
):
    
    print("getting current chunk of scenes...")
    
    with open("/scratch/indrisch/vllm_experiments/data/sqa-3d/ScanQA_format/the_650_scenes.txt", "r") as f:
        scenes = [x.replace("\n", "") for x in f.readlines()]
    f.close()
    
    scenes = get_chunk(scenes, num_chunks, chunk_idx)
    
    print(f'this run is using chunk {chunk_idx} of {num_chunks}')
    print("Number of scenes being used in this run: ", len(scenes))
    print("scenes: ", scenes)
    
    existing_scenes = get_existing_scenes(overwrite_existing_json, export_json_path)
    existing_scenes = [s["scene"] for s in existing_scenes]
    
    cumulative_time = 0.0
    scene_count = 0
    outputs_for_chunk = existing_scenes
    
    # Process each question
    for scene in scenes:
        
        print(f"========== Processing scene: {scene} ==========")
        
        if scene in existing_scenes:
            print(f"Scene {scene} already has been processed. Skipping, and deleting the folders.")
            delete_folders(scene)
            continue
        else:
            print(f"Scene {scene} has not been processed. Processing it.")
        
        start_time = time.time()
        # for each scene, we are going to:
        # - extract that dar file into a folder using dars_to_folders (if already extracted, this automatically does nothing)
        # - get the list of image files in the folder os.path.join(image_folder_path, scene, "color"), store this into output["image_files"]
        # - get how many images are in the folder os.path.join(image_folder_path, scene, "color"), store this into output["num_images"]
        # - delete the extracted folder by calling delete_folders(scene)
        
        dars_to_folders(image_folder_path, scene)
        image_folder = os.path.join(image_folder_path, scene, "color")
        image_files = os.listdir(image_folder)
        image_files = sorted(image_files, key=lambda n: int(n.split(".")[0])) # every image file name is a number, so we can sort by the number
        num_images = len(image_files)
        print("Number of images in the scene: ", num_images)
        delete_folders(scene)
        
        output = {"scene": scene, "image_files": image_files, "num_images": num_images}
        # Collect outputs in-memory; parent will write once after all workers complete
        outputs_for_chunk.append(output)
            
        end_time = time.time()
        time_taken = end_time - start_time
        cumulative_time += time_taken
        print(f"Time taken for scene {scene}: {time_taken:.2f} seconds")
        print("cumulative_time: ", cumulative_time)
        scene_count += 1
        print("scene_count: ", scene_count)
        print("average_time_per_scene: ", cumulative_time / scene_count)
        
        # with open(export_json_path, "w") as f:
        #     json.dump(outputs_for_chunk, f, indent=4)
        # f.close()
        
    return outputs_for_chunk


if __name__ == "__main__":
    
    start_time = time.time()
    
    # arguments
    parser = argparse.ArgumentParser()
    parser.add_argument("--cluster_name", type=str, required=True)
    parser.add_argument("--question_file", type=str, required=True)
    parser.add_argument("--answer_file", type=str, required=True)
    parser.add_argument("--image_folder", type=str, required=True)
    parser.add_argument("--export_json", type=str, required=True)
    parser.add_argument("--traces_json", type=str, required=True, help="path to file with generated traces")
    parser.add_argument("--overwrite_existing_json", action="store_true", help="Overwrite existing JSON file.")
    parser.add_argument("--model_path", type=str, default="Qwen/Qwen3-4B-Thinking-2507", help="Model path.")
    parser.add_argument("--device", type=str, default="cpu")
    parser.add_argument("--sample_rate", type=int, default=5)
    parser.add_argument("--num_chunks", type=int, default=1)
    parser.add_argument("--chunk_idx", type=int, default=0)
    parser.add_argument("--mc_traces", type=int, default=4, help="Number of traces to use for the MC question.")
    parser.add_argument("--batch_size", type=int, default=4, help="Batch size for progressive inference. If -1, the batch size will be set to the number of images in the question.")
    parser.add_argument("--sort_by_scene", action="store_true", help="Sort questions by scene.")
    parser.add_argument("--tensor_parallel_size", type=int, default=1, help="Number of GPUs for tensor parallelism.")
    args = parser.parse_args()
    print("args: ", args)
    

    # set environment variables
    cluster_name = args.cluster_name
    print("Cluster name: ", cluster_name)

    if cluster_name not in ["RORQUAL", "FIR", "NIBI", "NARVAL", "TRILLIUM"]:
        raise ValueError("Invalid cluster name")

    try:
        vllm_home = os.path.join(os.getcwd()[:os.getcwd().index("vllm_experiments")], "vllm_experiments")
    except ValueError:
        vllm_home = os.path.join(os.getcwd()[:os.getcwd().index("vllm")],"vllm")

    sys.path.insert(0, os.path.join(vllm_home, "kimi_vl_a3b_thinking_2506/kimivl_3d_test"))
    print(sys.path)

    import sysconfigtool
    os.environ["HF_HOME"] = sysconfigtool.read(cluster_name, "HF_HOME")
    os.environ["HF_HUB_CACHE"] = sysconfigtool.read(cluster_name, "HF_HUB_CACHE")
    os.environ["HF_HUB_DISABLE_XET"] = sysconfigtool.read(cluster_name, "HF_HUB_DISABLE_XET")

    print("HF_HOME: ", os.environ["HF_HOME"])
    print("HF_HUB_CACHE: ", os.environ["HF_HUB_CACHE"])
    print("HF_HUB_DISABLE_XET: ", os.environ["HF_HUB_DISABLE_XET"])

    # Run args.num_chunks workers; each processes its own chunk and accumulates results in-memory
    num_workers = args.num_chunks

    # Handle overwrite once in parent to avoid concurrent file operations
    if args.overwrite_existing_json and os.path.exists(args.export_json):
        os.remove(args.export_json)
        
    #_worker_run(args.chunk_idx, args, [])

    manager = multiprocessing.Manager()
    results = manager.list([[] for _ in range(num_workers)])

    processes = [
        multiprocessing.Process(target=_worker_run, args=(i, args, results))
        for i in range(num_workers)
    ]

    for p in processes:
        p.start()

    for p in processes:
        p.join()

    # Flatten list of lists
    all_outputs = []
    for sublist in list(results):
        all_outputs.extend(sublist)

    # Merge with existing (if not overwritten above)
    existing = []
    if not args.overwrite_existing_json:
        try:
            with open(args.export_json, "r") as f:
                existing = json.load(f)
        except FileNotFoundError:
            existing = []

    final_outputs = existing + all_outputs
    
    # final string removal and deduplication and sorting by scene name
    final_outputs = [d for d in final_outputs if isinstance(d, dict)]
    
    checklist = []
    for d in final_outputs:
        if d["scene"] not in checklist:
            checklist.append(d["scene"])
        else:
            print(f"Duplicate scene: {d['scene']}")
            # remove the duplicate
            final_outputs.remove(d)
            
    final_outputs = natsorted(final_outputs, key=lambda a: int(a["scene"][5:9] + a["scene"][10:]))

    with open(args.export_json, "w") as f:
        json.dump(final_outputs, f, indent=4)

    print(f"Wrote {len(final_outputs)} records to {args.export_json}")

    end_time = time.time()
    print(f"Total time taken: {end_time - start_time:.2f} seconds")

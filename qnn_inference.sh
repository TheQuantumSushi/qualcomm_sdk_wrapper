#!/bin/bash

# QNN Inference Runner with QNN Parser Integration
# Runs inference and creates CSV structure for metrics that will be filled

### PARAMETERS : ###

set -e

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
BLUE='\033[38;2;0;123;255m'
NC='\033[0m' # no color

# Default values :
MODEL_PATH=""
BACKEND=""
DATA_DIR=""
INPUT_LIST=""
VERBOSE=false
NUM_INFERENCES=1
PERF_PROFILE="balanced"
TIMEOUT=300 # 5 minutes default timeout
QNN_RUN_DIR="" # global variable for run directory
DEVICE=""

### HELPER FUNCTIONS : ###

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "success") echo -e "${GREEN}✓${NC} $message" ;;
        "error") echo -e "${RED}✗${NC} $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} $message" ;;
        "info") echo -e "${BLUE}ℹ${NC} $message" ;;
    esac
}

show_usage() {
    cat << EOF

${BLUE}QNN Inference Runner${NC}
${BLUE}====================${NC}

${GREEN}DESCRIPTION:${NC}
    Runs QNN model inference on connected Android devices with comprehensive 
    metrics collection. Creates initial CSV structure and saves detailed logs 
    for post-processing by extract_metrics.sh.

${GREEN}USAGE:${NC}
    $0 -m MODEL -b BACKEND -d DATA_DIR -l INPUT_LIST [OPTIONS]

${GREEN}REQUIRED ARGUMENTS:${NC}
    ${YELLOW}-m MODEL${NC}             Model file path (relative to PROJECT_ROOT/models/)
    ${YELLOW}-b BACKEND${NC}           Inference backend: cpu, gpu, htp
    ${YELLOW}-d DATA_DIR${NC}          Data directory path (relative to PROJECT_ROOT/data/)
    ${YELLOW}-l INPUT_LIST${NC}        Input list file path (relative to PROJECT_ROOT/data/)

${GREEN}OPTIONAL ARGUMENTS:${NC}
    ${YELLOW}-n NUM${NC}               Number of inference runs (default: auto-detect from input count)
    ${YELLOW}-p PROFILE${NC}           Performance profile: power_saver, balanced, burst (default: balanced)
    ${YELLOW}-t TIMEOUT${NC}           Timeout in seconds (default: 300)
    ${YELLOW}-v${NC}                  Enable verbose output showing detailed progress
    ${YELLOW}-h${NC}                  Show this help message

${GREEN}BACKEND OPTIONS:${NC}
    ${YELLOW}cpu${NC}                  CPU execution (libQnnCpu.so)
    ${YELLOW}gpu${NC}                  GPU execution (libQnnGpu.so)
    ${YELLOW}htp${NC}                  NPU/HTP execution (libQnnHtp.so) - requires Hexagon libraries

${GREEN}PERFORMANCE PROFILES:${NC}
    ${YELLOW}power_saver${NC}          Optimize for power efficiency
    ${YELLOW}balanced${NC}             Balance between performance and power (default)
    ${YELLOW}burst${NC}                Maximum performance mode

${GREEN}EXAMPLES:${NC}
    # Basic inference with HTP backend
    $0 -m model_quantized.so -b htp -d detection/test/raw -l input_list.txt

    # CPU inference with custom performance profile and timeout
    $0 -m model.so -b cpu -d dataset -l inputs.txt -p burst -t 600

    # Verbose inference with specific number of runs
    $0 -m model.so -b gpu -d validation -l test_inputs.txt -n 10 -v

${GREEN}INPUT LIST FORMAT:${NC}
    Text file containing input filenames (one per line):
    image001.raw
    image002.raw
    # Comments are ignored

${GREEN}DEVICE REQUIREMENTS:${NC}
    • Android device connected via ADB
    • Sufficient storage space in /data/local/tmp/
    • QNN runtime libraries (transferred automatically)
    • For HTP: Hexagon DSP libraries and drivers

${GREEN}OUTPUT:${NC}
    Creates timestamped run directory on device with:
    • Run ID: qnn_run_YYYYMMDD_HHMMSS
    • Initial metrics.csv with basic run information
    • Detailed QNN output logs for post-processing
    • Inference result files (.raw/.bin)

${GREEN}WORKFLOW:${NC}
    1. Device selection (if multiple devices connected)
    2. File transfer (model, data, QNN libraries)
    3. Inference execution with profiling
    4. Result validation and metrics collection
    5. Log saving for extract_metrics.sh processing

${GREEN}NEXT STEPS:${NC}
    After inference completion, use qnn_pull.sh to:
    • Retrieve results from device
    • Process logs with extract_metrics.sh
    • Generate complete performance metrics

${GREEN}REQUIREMENTS:${NC}
    • QUALCOMM_ROOT and PROJECT_ROOT environment variables
    • QNN SDK with aarch64-oe-linux-gcc11.2 binaries
    • Connected Android device with ADB debugging enabled
    • jq for configuration parsing

EOF

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m) MODEL_PATH="$2"; shift 2 ;;
            -b) BACKEND="$2"; shift 2 ;;
            -d) DATA_DIR="$2"; shift 2 ;;
            -l) INPUT_LIST="$2"; shift 2 ;;
            -n) NUM_INFERENCES="$2"; shift 2 ;;
            -p) PERF_PROFILE="$2"; shift 2 ;;
            -t) TIMEOUT="$2"; shift 2 ;;
            -v) VERBOSE=true; shift ;;
            -h) show_usage; exit 0 ;;
            *) echo "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done
}

setup_environment() {
    print_status "info" "Setting up environment"
    
    # Set QUALCOMM_ROOT if not set
    if [ -z "$QUALCOMM_ROOT" ]; then
        export QUALCOMM_ROOT=".."
    fi
    
    # Load config
    local config_file="$QUALCOMM_ROOT/scripts/config.json"
    if [ ! -f "$config_file" ]; then
        print_status "error" "Config file not found: $config_file"
        exit 1
    fi
    
    # Export variables
    export QNN_ROOT=$(jq -r '.environment_variables.QNN_ROOT' "$config_file" | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
    export PROJECT_ROOT="$QUALCOMM_ROOT/projects/$(jq -r '.names.project' "$config_file")"
    
    print_status "success" "Environment configured"
}

validate_inputs() {
    print_status "info" "Validating inputs"
    
    # Check required arguments
    if [[ -z "$MODEL_PATH" || -z "$BACKEND" || -z "$DATA_DIR" || -z "$INPUT_LIST" ]]; then
        print_status "error" "Missing required arguments"
        show_usage
        exit 1
    fi
    
    # Validate backend
    if [[ ! "$BACKEND" =~ ^(cpu|gpu|htp)$ ]]; then
        print_status "error" "Invalid backend: $BACKEND"
        exit 1
    fi
    
    # Check files exist
    local model_file="$PROJECT_ROOT/models/$MODEL_PATH"
    local data_path="$PROJECT_ROOT/data/$DATA_DIR"
    local list_file="$PROJECT_ROOT/data/$INPUT_LIST"
    
    if [ ! -f "$model_file" ]; then
        print_status "error" "Model not found: $model_file"
        exit 1
    fi
    
    if [ ! -d "$data_path" ]; then
        print_status "error" "Data directory not found: $data_path"
        exit 1
    fi
    
    if [ ! -f "$list_file" ]; then
        print_status "error" "Input list not found: $list_file"
        exit 1
    fi
    
    print_status "success" "All inputs validated"
}

select_device() {
    print_status "info" "Selecting device"
    
    local devices=($(adb devices | grep "device$" | awk '{print $1}'))
    
    if [ ${#devices[@]} -eq 0 ]; then
        print_status "error" "No devices connected"
        exit 1
    elif [ ${#devices[@]} -eq 1 ]; then
        DEVICE="${devices[0]}"
        print_status "success" "Using device: $DEVICE"
    else
        echo "Multiple devices found:"
        for i in "${!devices[@]}"; do
            echo "  $((i+1)). ${devices[$i]}"
        done
        read -p "Select device (1-${#devices[@]}): " selection
        DEVICE="${devices[$((selection-1))]}"
        print_status "success" "Selected device: $DEVICE"
    fi
    
    # Test connection
    adb -s "$DEVICE" shell "echo 'test'" >/dev/null 2>&1 || {
        print_status "error" "Cannot connect to device"
        exit 1
    }
}

check_file_exists_on_device() {
    local file_path="$1"
    adb -s "$DEVICE" shell "test -f '$file_path'" >/dev/null 2>&1
}

transfer_files() {
    print_status "info" "Transferring files to device"
    
    local device_home="/data/local/tmp"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local run_dir="qnn_run_${timestamp}"
    
    # Save run dir to global variable
    QNN_RUN_DIR="$run_dir"
    
    print_status "info" "Created run directory: $run_dir"
    
    # Create device directories
    adb -s "$DEVICE" shell "mkdir -p /opt $device_home/$run_dir/{model,data,results,metrics}" >/dev/null 2>&1
    
    # Transfer QNN binaries and libraries with existence check
    print_status "info" "Checking and transferring QNN runtime components"
    
    if [ -d "$QNN_ROOT/bin/aarch64-oe-linux-gcc11.2/" ]; then
        find "$QNN_ROOT/bin/aarch64-oe-linux-gcc11.2/" -name "qnn-*" -type f | while read file; do
            local basename_file=$(basename "$file")
            local device_path="/opt/$basename_file"
            
            if check_file_exists_on_device "$device_path"; then
                [ "$VERBOSE" = true ] && print_status "info" "Skipping $basename_file (already exists)"
            else
                [ "$VERBOSE" = true ] && echo "  Pushing $(basename "$file")"
                adb -s "$DEVICE" push "$file" "/opt/" >/dev/null 2>&1
            fi
        done
    fi
    
    if [ -d "$QNN_ROOT/lib/aarch64-oe-linux-gcc11.2/" ]; then
        find "$QNN_ROOT/lib/aarch64-oe-linux-gcc11.2/" -name "libQnn*.so" -type f | while read file; do
            local basename_file=$(basename "$file")
            local device_path="/opt/$basename_file"
            
            if check_file_exists_on_device "$device_path"; then
                [ "$VERBOSE" = true ] && print_status "info" "Skipping $basename_file (already exists)"
            else
                [ "$VERBOSE" = true ] && echo "  Pushing $(basename "$file")"
                adb -s "$DEVICE" push "$file" "/opt/" >/dev/null 2>&1
            fi
        done
    fi
    
    # Transfer Hexagon libraries for HTP with existence check
    if [ "$BACKEND" = "htp" ] && [ -d "$QNN_ROOT/lib/hexagon-v68/unsigned" ]; then
        print_status "info" "Checking Hexagon libraries for HTP backend"
        find "$QNN_ROOT/lib/hexagon-v68/unsigned/" -type f | while read file; do
            local basename_file=$(basename "$file")
            local device_path="/opt/$basename_file"
            
            if check_file_exists_on_device "$device_path"; then
                [ "$VERBOSE" = true ] && print_status "info" "Skipping $basename_file (already exists)"
            else
                [ "$VERBOSE" = true ] && echo "  Pushing $(basename "$file")"
                adb -s "$DEVICE" push "$file" "/opt/" >/dev/null 2>&1
            fi
        done
    fi
    
    # Transfer model
    local model_file="$PROJECT_ROOT/models/$MODEL_PATH"
    adb -s "$DEVICE" push "$model_file" "$device_home/$run_dir/model/" >/dev/null 2>&1
    
    # Transfer data
    adb -s "$DEVICE" push "$PROJECT_ROOT/data/$DATA_DIR/." "$device_home/$run_dir/data/" >/dev/null 2>&1
    
    # Create corrected input list (filenames only)
    local temp_list="/tmp/input_list_$$.txt"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        basename "$line"
    done < "$PROJECT_ROOT/data/$INPUT_LIST" > "$temp_list"
    
    adb -s "$DEVICE" push "$temp_list" "$device_home/$run_dir/data/input_list.txt" >/dev/null 2>&1
    rm -f "$temp_list"
    
    print_status "success" "Files transferred to device"
}

create_initial_csv() {
    local run_dir="$1"
    local device_home="/data/local/tmp"
    local work_dir="$device_home/$run_dir"
    
    print_status "info" "Creating initial CSV structure"
    
    # Create CSV header with basic info (timestamp to output_files_count) and new metrics
    local csv_header="timestamp,run_id,model,backend,device,perf_profile,success,total_time_seconds,output_files_count"
    
    # Add new performance metrics (columns 10-24)
    csv_header="$csv_header,minimum_unit_inference_time_ms,minimum_unit_inference_file"
    csv_header="$csv_header,maximum_unit_inference_time_ms,maximum_unit_inference_file"
    csv_header="$csv_header,median_unit_inference_time_ms,average_unit_inference_time_ms"
    csv_header="$csv_header,backend_creation_ms,graph_composition_ms,graph_finalization_ms"
    csv_header="$csv_header,graph_execution_ms,total_inference_ms"
    csv_header="$csv_header,ddr_spill_B,ddr_fill_B,ddr_write_total_B,ddr_read_total_B"
    
    # Basic run info (filled by bash)
    local timestamp=$(date -Iseconds)
    local model_basename=$(basename "$MODEL_PATH")
    
    # Initialize CSV with basic info that bash can provide
    local csv_data="$timestamp,$run_dir,$model_basename,$BACKEND,$DEVICE,$PERF_PROFILE,pending,0,0"
    
    # Add placeholders for all new performance metrics (15 columns total)
    # Columns 10-24: min_time, min_file, max_time, max_file, median, avg, backend, compose, finalize, exec, total, spill, fill, write, read
    csv_data="$csv_data,0,input_0,0,input_0,0,0,0,0,0,0,0,0,0,0,0"
    
    # Create CSV file locally
    local temp_csv="/tmp/qnn_initial_metrics_$$.csv"
    echo "$csv_header" > "$temp_csv"
    echo "$csv_data" >> "$temp_csv"
    
    # Transfer CSV to device
    if adb -s "$DEVICE" push "$temp_csv" "$work_dir/metrics/metrics.csv" >/dev/null 2>&1; then
        print_status "success" "Initial CSV structure created"
    else
        print_status "error" "Failed to create initial CSV"
        exit 1
    fi
    
    # Cleanup
    rm -f "$temp_csv"
}

run_inference() {
    # Use the global run directory variable
    local run_dir="$QNN_RUN_DIR"
    local device_home="/data/local/tmp"
    local work_dir="$device_home/$run_dir"
    
    print_status "info" "Running inference with $BACKEND backend"
    
    # Create initial CSV structure
    create_initial_csv "$run_dir"
    
    # Set up environment
    local env_setup="export LD_LIBRARY_PATH=/opt:\$LD_LIBRARY_PATH; export PATH=/opt:\$PATH"
    if [ "$BACKEND" = "htp" ]; then
        env_setup="$env_setup; export ADSP_LIBRARY_PATH=\"/opt;/usr/lib/rfsa/adsp;/dsp\""
    fi
    
    # Determine backend library and output directory
    local backend_lib output_dir
    case "$BACKEND" in
        cpu) backend_lib="libQnnCpu.so"; output_dir="output_cpu" ;;
        gpu) backend_lib="libQnnGpu.so"; output_dir="output_gpu" ;;
        htp) backend_lib="libQnnHtp.so"; output_dir="output_htp" ;;
    esac
    
    # Build inference command with correct paths and profiling enabled
    local model_name=$(basename "$MODEL_PATH")
    
    # Count input files to determine correct num_inferences
    local input_count=$(adb -s "$DEVICE" shell "wc -l < $work_dir/data/input_list.txt" | tr -d '\r\n' || echo "1")
    print_status "info" "Found $input_count input files for processing"
    
    local inference_cmd="cd $work_dir/data && timeout $TIMEOUT qnn-net-run"
    inference_cmd="$inference_cmd --model ../model/$model_name"
    inference_cmd="$inference_cmd --backend $backend_lib"
    inference_cmd="$inference_cmd --input_list input_list.txt"
    inference_cmd="$inference_cmd --use_native_input_files"
    inference_cmd="$inference_cmd --output_dir ../results/$output_dir"
    inference_cmd="$inference_cmd --profiling_level basic"
    inference_cmd="$inference_cmd --num_inferences $input_count"
    inference_cmd="$inference_cmd --keep_num_outputs $input_count"
    
    # Add performance options
    if [ "$PERF_PROFILE" != "balanced" ]; then
        inference_cmd="$inference_cmd --perf_profile $PERF_PROFILE"
    fi
    
    # Add logging for metrics extraction
    inference_cmd="$inference_cmd --log_level INFO"
    
    # Create a temporary script on device for better process control
    local temp_script="/tmp/qnn_run_$$.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
$env_setup
$inference_cmd
echo "INFERENCE_EXIT_CODE:\$?"
echo "INFERENCE_COMPLETED_TIMESTAMP:\$(date +%s.%N)"
EOF
    
    # Transfer script to device
    adb -s "$DEVICE" push "$temp_script" "$work_dir/run_inference.sh" >/dev/null 2>&1
    adb -s "$DEVICE" shell "chmod +x $work_dir/run_inference.sh" >/dev/null 2>&1
    rm -f "$temp_script"
    
    # Execute inference with timeout and proper termination
    local start_time=$(date +%s.%N)
    print_status "info" "Starting inference (timeout: ${TIMEOUT}s)..."
    
    local inference_output
    local inference_result
    
    # Run with timeout and capture all output
    inference_output=$(timeout $((TIMEOUT + 10)) adb -s "$DEVICE" shell "$work_dir/run_inference.sh" 2>&1)
    inference_result=$?
    
    local end_time=$(date +%s.%N)
    local total_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Display output if verbose or if there was an error
    if [ "$VERBOSE" = true ] || [ $inference_result -ne 0 ]; then
        echo "$inference_output"
    fi
    
    # Enhanced success detection
    local success=false
    local exit_code_line=$(echo "$inference_output" | grep "INFERENCE_EXIT_CODE:" | tail -1)
    local actual_exit_code=""
    
    if [ -n "$exit_code_line" ]; then
        actual_exit_code=$(echo "$exit_code_line" | cut -d: -f2 | tr -d ' ')
    fi
    
    # Check for successful completion indicators
    local has_finished_graphs=$(echo "$inference_output" | grep -q "Finished Executing Graphs" && echo "true" || echo "false")
    local has_backend_free=$(echo "$inference_output" | grep -q "QnnBackend_free started" && echo "true" || echo "false")
    
    # Check for actual output files before declaring success
    print_status "info" "Checking for output files..."
    local output_count=$(adb -s "$DEVICE" shell "find $work_dir/results/ -type f \( -name '*.raw' -o -name '*.bin' \) 2>/dev/null | wc -l" | tr -d '\r\n' || echo "0")
    
    # Success criteria: exit code 0 AND proper execution sequence
    if [ "$actual_exit_code" = "0" ]; then
        if [ "$has_finished_graphs" = "true" ] && [ "$has_backend_free" = "true" ] && [ "$output_count" -gt 0 ]; then
            success=true
            print_status "success" "Inference completed successfully"
            print_status "info" "✓ Exit code: $actual_exit_code"
            print_status "info" "✓ Graphs executed and freed properly"
            print_status "info" "✓ Generated $output_count output files"
        elif [ "$output_count" -gt 0 ]; then
            success=true
            print_status "success" "Inference completed - $output_count output files generated"
            print_status "warning" "Some cleanup steps may have been incomplete"
        else
            print_status "error" "Inference completed but no output files were generated"
        fi
    elif [ $inference_result -eq 124 ]; then
        print_status "error" "Inference timed out after ${TIMEOUT} seconds"
    elif [ $inference_result -ne 0 ]; then
        print_status "error" "Inference failed with exit code: $inference_result"
    else
        if [ "$output_count" -gt 0 ]; then
            success=true
            print_status "success" "Inference completed - $output_count output files generated"
            print_status "warning" "Exit code unclear but outputs were generated"
        else
            print_status "error" "Inference failed - no output files generated"
        fi
    fi
    
    if [ "$success" = false ]; then
        print_status "error" "Inference failed or produced no output"
        echo "=== Debug Information ==="
        echo "Exit code: $actual_exit_code"
        echo "Output files found: $output_count"
        echo "Has finished graphs: $has_finished_graphs"
        echo "Has backend free: $has_backend_free"
        echo "=== Full Output ==="
        echo "$inference_output"
        exit 1
    fi
    
    # Update CSV with basic completion info
    update_basic_csv_info "$run_dir" "$success" "$total_time" "$output_count"
    
    # Save QNN output for parser processing later
    save_qnn_output "$run_dir" "$inference_output"
    
    print_status "success" "Results saved on device in: $run_dir"
    print_status "info" "Use qnn_pull.sh to retrieve and process with QNN parser"
    echo "Run ID: $run_dir"
}

update_basic_csv_info() {
    local run_dir="$1"
    local success="$2"
    local total_time="$3"
    local output_count="$4"
    local device_home="/data/local/tmp"
    local work_dir="$device_home/$run_dir"
    
    print_status "info" "Updating CSV with basic completion info"
    
    # Pull current CSV
    local temp_csv="/tmp/update_csv_$$.csv"
    if adb -s "$DEVICE" pull "$work_dir/metrics/metrics.csv" "$temp_csv" >/dev/null 2>&1; then
        # Update the data row (second line) with success info
        local header=$(head -1 "$temp_csv")
        local data=$(tail -1 "$temp_csv")
        
        # Replace success and timing info in the data row
        # Format: timestamp,run_id,model,backend,device,perf_profile,success,total_time_seconds,output_files_count,...
        local updated_data=$(echo "$data" | awk -F',' -v success="$success" -v time="$total_time" -v count="$output_count" '
        {
            $7 = success
            $8 = time
            $9 = count
            print
        }' OFS=',')
        
        # Write updated CSV
        echo "$header" > "$temp_csv"
        echo "$updated_data" >> "$temp_csv"
        
        # Push back to device
        adb -s "$DEVICE" push "$temp_csv" "$work_dir/metrics/metrics.csv" >/dev/null 2>&1
        print_status "success" "CSV updated with completion status"
    else
        print_status "warning" "Could not update CSV with completion info"
    fi
    
    rm -f "$temp_csv"
}

save_qnn_output() {
    local run_dir="$1"
    local output="$2"
    local device_home="/data/local/tmp"
    
    print_status "info" "Saving QNN output for parser processing"
    
    # Save QNN output to device
    local output_file="/tmp/qnn_output_$$.txt"
    echo "$output" > "$output_file"
    if adb -s "$DEVICE" push "$output_file" "$device_home/$run_dir/metrics/qnn_output.txt" >/dev/null 2>&1; then
        print_status "success" "QNN output saved for parser"
    else
        print_status "warning" "Failed to save QNN output"
    fi
    
    # Get and save system info
    local device_info_file="/tmp/device_info_$$"
    if adb -s "$DEVICE" shell "getprop ro.product.model; getprop ro.build.version.release; getprop ro.product.cpu.abi; date" > "$device_info_file" 2>/dev/null; then
        if adb -s "$DEVICE" push "$device_info_file" "$device_home/$run_dir/metrics/device_info.txt" >/dev/null 2>&1; then
            print_status "success" "Device info saved"
        fi
    fi
    
    # Cleanup temp files
    rm -f "$output_file" "$device_info_file"
}

cleanup_on_exit() {
    # Clean up temp files on exit
    rm -f "/tmp/device_info_$$" "/tmp/qnn_initial_metrics_$$.csv" "/tmp/input_list_$$.txt" "/tmp/qnn_run_$$.sh" "/tmp/qnn_output_$$.txt" "/tmp/update_csv_$$.csv"
}

main() {
    # Set up cleanup trap
    trap cleanup_on_exit EXIT
    
    echo "Enhanced QNN Inference Runner with Parser Integration"
    echo "===================================================="
    
    parse_arguments "$@"
    setup_environment
    validate_inputs
    select_device
    transfer_files
    run_inference
    
    echo
    echo "Inference completed successfully!"
    echo "Device: $DEVICE"
    echo "Model: $MODEL_PATH"
    echo "Backend: $BACKEND"
    echo "CSV structure created - metrics will be filled by qnn_pull.sh"
    echo "Use ./qnn_pull.sh to retrieve results and complete metrics processing"
    
    exit 0
}

main "$@"

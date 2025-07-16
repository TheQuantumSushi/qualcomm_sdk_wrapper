#!/bin/bash

# Batch QNN Inference Runner
# Automatically runs multiple inference tests and compiles comprehensive metrics into CSV

### PARAMETERS : ###

# NOTE: We deliberately DO NOT use 'set -e' here because we want to handle errors
# gracefully and continue processing other models in the batch

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
BLUE='\033[38;2;0;123;255m'
NC='\033[0m' # no color

# Default values :
CONFIG_FILE=""
OUTPUT_METRICS_CSV=""
OUTPUT_INPUT_TIMES_CSV=""
DATA_DIR=""
INPUT_LIST=""
VERBOSE=false
DRY_RUN=false
CONTINUE_ON_ERROR=true
CLEANUP_RUNS=false
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Device selection variables for batch operation
SELECTED_DEVICE=""
SELECTED_DEVICE_NUMBER=""

### HELPER FUNCTIONS : ###

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "success") echo -e "# ${GREEN}✔${NC} $message" ;;
        "error") echo -e "# ${RED}✗${NC} $message" ;;
        "warning") echo -e "# ${YELLOW}⚠${NC} $message" ;;
        "info") echo -e "# ${BLUE}ℹ${NC} $message" ;;
    esac
}

print_section_header() {
    local title="$1"
    local length=${#title}
    local separator_length=$((length + 4))
    local separator=$(printf '%*s' "$separator_length" '' | tr ' ' '=')
    
    echo
    echo "$separator"
    echo "  $title"
    echo "$separator"
    echo
}

print_subsection() {
    local title="$1"
    local length=${#title}
    local separator_length=$((length + 4))
    local separator=$(printf '%*s' "$separator_length" '' | tr ' ' '-')
    
    echo
    echo "$separator"
    echo "  $title"
    echo "$separator"
}

show_usage() {
    cat << EOF

${BLUE}Batch QNN Inference Runner${NC}
${BLUE}==========================${NC}

${GREEN}DESCRIPTION:${NC}
    Automatically runs multiple QNN models for inference testing and compiles 
    comprehensive performance metrics into CSV files. Each model uses the same 
    data directory and input list for consistent comparison.

${GREEN}USAGE:${NC}
    $0 -c CONFIG_FILE -d DATA_DIR -l INPUT_LIST [OPTIONS]

${GREEN}REQUIRED ARGUMENTS:${NC}
    ${YELLOW}-c CONFIG_FILE${NC}      JSON configuration file containing model definitions
    ${YELLOW}-d DATA_DIR${NC}         Data directory path (relative to PROJECT_ROOT/data/)
    ${YELLOW}-l INPUT_LIST${NC}       Input list file path (relative to PROJECT_ROOT/data/)

${GREEN}OPTIONAL ARGUMENTS:${NC}
    ${YELLOW}-m OUTPUT_PREFIX${NC}    Output CSV file prefix (default: batch_results_TIMESTAMP)
    ${YELLOW}-v${NC}                  Enable verbose output showing detailed progress
    ${YELLOW}-n${NC}                  Dry run mode - show execution plan without running
    ${YELLOW}-k${NC}                  Continue on error - don't stop if one model fails [DEFAULT]
    ${YELLOW}-s${NC}                  Stop on first error (opposite of -k)
    ${YELLOW}-r${NC}                  Remove run directories after pulling results
    ${YELLOW}-h${NC}                  Show this help message

${GREEN}CONFIGURATION FILE FORMAT:${NC}
    JSON file defining models to test:
    {
      "models": [
        {
          "name": "model1_htp",           // Display name for model
          "file_path": "model1.so",       // Path relative to PROJECT_ROOT/models/
          "backend": "htp",               // Backend: cpu, gpu, or htp
          "run_count": 1,                 // Number of inference runs (optional)
          "perf_profile": "balanced",     // Performance profile (optional)
          "timeout": 300                  // Timeout in seconds (optional)
        }
      ]
    }

${GREEN}OUTPUT FILES:${NC}
    Two CSV files are generated with timestamp suffix:
    • batch_metrics_TIMESTAMP.csv       - Model performance metrics
    • batch_input_times_TIMESTAMP.csv   - Individual input execution times

${GREEN}EXAMPLES:${NC}
    # Basic batch inference with 3 models
    $0 -c model_configs.json -d detection/test/raw -l input_list.txt

    # Verbose run with custom output prefix
    $0 -c models.json -d validation/data -l inputs.txt -m my_experiment -v

    # Dry run to preview execution without running
    $0 -c models.json -d test_data -l test_inputs.txt -n -v

    # Run with cleanup and stop on first error
    $0 -c models.json -d data -l inputs.txt -r -s

${GREEN}WORKFLOW:${NC}
    1. Device selection for all operations
    2. Validate configuration and data paths
    3. Run inference for each model sequentially
    4. Pull results and extract metrics automatically
    5. Compile all metrics into batch CSV files
    6. Optional cleanup of run directories

${GREEN}REQUIREMENTS:${NC}
    - QUALCOMM_ROOT environment variable set
    - PROJECT_ROOT derived from config.json
    - Connected Android device via ADB
    - jq, adb, and python3 available
    - QNN SDK properly configured

EOF
}

parse_arguments() {
    print_section_header "Parsing Command Line Arguments"
    
    local output_prefix=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c) CONFIG_FILE="$2"; print_status "info" "Config file: $CONFIG_FILE"; shift 2 ;;
            -d) DATA_DIR="$2"; print_status "info" "Data directory: $DATA_DIR"; shift 2 ;;
            -l) INPUT_LIST="$2"; print_status "info" "Input list: $INPUT_LIST"; shift 2 ;;
            -m) output_prefix="$2"; print_status "info" "Output prefix: $output_prefix"; shift 2 ;;
            -v) VERBOSE=true; print_status "info" "Verbose mode enabled"; shift ;;
            -n) DRY_RUN=true; print_status "info" "Dry run mode enabled"; shift ;;
            -k) CONTINUE_ON_ERROR=true; print_status "info" "Continue on error enabled"; shift ;;
            -s) CONTINUE_ON_ERROR=false; print_status "info" "Stop on first error enabled"; shift ;;
            -r) CLEANUP_RUNS=true; print_status "info" "Cleanup runs enabled"; shift ;;
            -h) show_usage; exit 0 ;;
            *) 
                print_status "error" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check required arguments
    if [[ -z "$CONFIG_FILE" || -z "$DATA_DIR" || -z "$INPUT_LIST" ]]; then
        print_status "error" "Missing required arguments"
        show_usage
        exit 1
    fi
    
    # Set default output CSV files if not specified
    if [[ -z "$output_prefix" ]]; then
        output_prefix="batch_results_$(date +%Y%m%d_%H%M%S)"
    fi
    
    OUTPUT_METRICS_CSV="${output_prefix}_metrics.csv"
    OUTPUT_INPUT_TIMES_CSV="${output_prefix}_input_times.csv"
    
    print_status "info" "Output metrics CSV: $OUTPUT_METRICS_CSV"
    print_status "info" "Output input times CSV: $OUTPUT_INPUT_TIMES_CSV"
    
    print_status "success" "Arguments parsed successfully"
}

setup_environment() {
    print_section_header "Environment Setup"
    
    # Set QUALCOMM_ROOT if not set
    if [ -z "$QUALCOMM_ROOT" ]; then
        export QUALCOMM_ROOT=".."
        print_status "info" "QUALCOMM_ROOT set to: $QUALCOMM_ROOT"
    else
        print_status "info" "Using existing QUALCOMM_ROOT: $QUALCOMM_ROOT"
    fi
    
    # Check if required tools are available
    print_status "info" "Checking required tools..."
    
    local missing_tools=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_tools+=("jq")
    fi
    
    if ! command -v adb >/dev/null 2>&1; then
        missing_tools+=("adb")
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        missing_tools+=("python3")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_status "error" "Missing required tools: ${missing_tools[*]}"
        print_status "info" "Please install missing tools and try again"
        exit 1
    fi
    
    print_status "success" "All required tools available"
    
    # Check if other scripts exist
    print_status "info" "Checking for required scripts..."
    
    local inference_script="$SCRIPT_DIR/qnn_inference.sh"
    local pull_script="$SCRIPT_DIR/qnn_pull.sh"
    local extract_script="$SCRIPT_DIR/extract_metrics.sh"
    
    if [ ! -f "$inference_script" ]; then
        print_status "error" "qnn_inference.sh not found in $SCRIPT_DIR"
        exit 1
    fi
    
    if [ ! -f "$pull_script" ]; then
        print_status "error" "qnn_pull.sh not found in $SCRIPT_DIR"
        exit 1
    fi
    
    if [ ! -f "$extract_script" ]; then
        print_status "error" "extract_metrics.sh not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Make scripts executable
    chmod +x "$inference_script" "$pull_script" "$extract_script"
    
    print_status "success" "Required scripts found and made executable"
    
    # Set up PROJECT_ROOT
    local config_file="$QUALCOMM_ROOT/scripts/config.json"
    if [ -f "$config_file" ]; then
        export PROJECT_ROOT="$QUALCOMM_ROOT/projects/$(jq -r '.names.project' "$config_file")"
    else
        export PROJECT_ROOT="$QUALCOMM_ROOT/projects/default"
    fi
    
    print_status "info" "PROJECT_ROOT: $PROJECT_ROOT"
}

select_device_for_batch() {
    print_section_header "Device Selection for Batch Operation"
    
    print_status "info" "Checking available devices for batch operation..."
    local devices=($(adb devices | grep -E "\s+device$" | cut -f1))
    
    if [ ${#devices[@]} -eq 0 ]; then
        print_status "error" "No devices found"
        return 1
    fi
    
    print_status "success" "Found ${#devices[@]} device(s)"
    echo
    echo "Available devices:"
    for i in "${!devices[@]}"; do
        echo "  $((i+1)). ${devices[$i]}"
    done
    
    echo
    while true; do
        read -p "Select device for batch operation (1-${#devices[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#devices[@]} ]; then
            SELECTED_DEVICE="${devices[$((choice-1))]}"
            SELECTED_DEVICE_NUMBER="$choice"
            print_status "success" "Selected device: $SELECTED_DEVICE"
            print_status "info" "Device will be used for all pull operations in this batch"
            return 0
        fi
        print_status "error" "Invalid selection. Please enter a number between 1 and ${#devices[@]}"
    done
}

find_run_number_from_run_id() {
    """
    Find the run number (position) of a specific run_id on the selected device.
    
    Args:
        - target_run_id [string] : The run_id to find (e.g., qnn_run_20250715_143022)
        - device_id [string] : The ADB device ID
    
    Returns:
        - integer : The 1-based position of the run (for use with pull script)
    """
    local target_run_id="$1"
    local device_id="$2"
    
    if [ -z "$target_run_id" ] || [ -z "$device_id" ]; then
        print_status "error" "find_run_number_from_run_id: Missing required parameters"
        return 1
    fi
    
    # Get list of QNN runs from device
    local runs=($(adb -s "$device_id" shell "ls -1 /data/local/tmp 2>/dev/null | grep '^qnn_run_'" 2>/dev/null | tr -d '\r'))
    
    if [ ${#runs[@]} -eq 0 ]; then
        print_status "error" "No QNN runs found on device"
        return 1
    fi
    
    # Find the index of our target run_id
    for i in "${!runs[@]}"; do
        if [ "${runs[$i]}" = "$target_run_id" ]; then
            echo "$((i + 1))"  # Return 1-based index for pull script
            return 0
        fi
    done
    
    # Not found
    print_status "error" "Run $target_run_id not found on device"
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Available runs on device:"
        for i in "${!runs[@]}"; do
            echo "  $((i+1)). ${runs[$i]}"
        done
    fi
    return 1
}

validate_config() {
    print_section_header "Configuration Validation"
    
    print_status "info" "Validating configuration file: $CONFIG_FILE"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_status "error" "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Check if JSON is valid
    if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        print_status "error" "Invalid JSON in configuration file"
        exit 1
    fi
    
    print_status "success" "Configuration file is valid JSON"
    
    # Check if models array exists
    local models_count=$(jq '.models | length' "$CONFIG_FILE" 2>/dev/null)
    if [ "$models_count" -eq 0 ] 2>/dev/null; then
        print_status "error" "No models found in configuration file"
        exit 1
    fi
    
    print_status "success" "Found $models_count model(s) in configuration"
    
    # Validate global data directory and input list
    print_subsection "Data Directory and Input List Validation"
    
    local data_path="$PROJECT_ROOT/data/$DATA_DIR"
    local list_file="$PROJECT_ROOT/data/$INPUT_LIST"
    
    echo "Checking global data paths:"
    echo "│"
    
    if [ -d "$data_path" ]; then
        echo -e "├── ${GREEN}✔${NC} Data directory: $data_path"
    else
        echo -e "├── ${RED}✗${NC} Data directory: $data_path"
        print_status "error" "Data directory not found: $data_path"
        exit 1
    fi
    
    if [ -f "$list_file" ]; then
        echo -e "└── ${GREEN}✔${NC} Input list: $list_file"
    else
        echo -e "└── ${RED}✗${NC} Input list: $list_file"
        print_status "error" "Input list not found: $list_file"
        exit 1
    fi
    
    echo
    print_status "success" "Global data directory and input list validated"
    
    # Validate each model configuration
    print_subsection "Model Configuration Validation"
    
    local validation_errors=0
    
    for i in $(seq 0 $((models_count - 1))); do
        local model_name=$(jq -r ".models[$i].name // \"model_$i\"" "$CONFIG_FILE")
        local file_path=$(jq -r ".models[$i].file_path // \"\"" "$CONFIG_FILE")
        local backend=$(jq -r ".models[$i].backend // \"\"" "$CONFIG_FILE")
        
        echo -e "Model [$((i+1))/$models_count]: ${BLUE}$model_name${NC}"
        
        # Validate required fields
        if [ -z "$file_path" ]; then
            print_status "error" "  Missing file_path for model: $model_name"
            ((validation_errors++))
        else
            # Check if model file exists
            local model_file="$PROJECT_ROOT/models/$file_path"
            if [ -f "$model_file" ]; then
                print_status "info" "  ✓ Model file: $file_path"
            else
                print_status "error" "  Model file not found: $file_path"
                ((validation_errors++))
            fi
        fi
        
        if [ -z "$backend" ]; then
            print_status "error" "  Missing backend for model: $model_name"
            ((validation_errors++))
        elif [[ ! "$backend" =~ ^(cpu|gpu|htp)$ ]]; then
            print_status "error" "  Invalid backend '$backend' for model: $model_name (must be: cpu, gpu, htp)"
            ((validation_errors++))
        else
            print_status "info" "  ✓ Backend: $backend"
        fi
        
        # Show that this model will use the global data settings
        print_status "info" "  → Uses global data directory: $DATA_DIR"
        print_status "info" "  → Uses global input list: $INPUT_LIST"
        
        echo
    done
    
    if [ $validation_errors -gt 0 ]; then
        print_status "error" "Configuration validation failed with $validation_errors error(s)"
        exit 1
    fi
    
    print_status "success" "All model configurations are valid"
}

initialize_csv_files() {
    print_section_header "CSV Initialization"
    
    print_status "info" "Creating output CSV files"
    
    # Create metrics CSV header
    local metrics_header="timestamp,run_id,model,backend,device,perf_profile,success,total_time_seconds,output_files_count"
    metrics_header="$metrics_header,minimum_unit_inference_time_ms,minimum_unit_inference_file"
    metrics_header="$metrics_header,maximum_unit_inference_time_ms,maximum_unit_inference_file"
    metrics_header="$metrics_header,median_unit_inference_time_ms,average_unit_inference_time_ms"
    metrics_header="$metrics_header,backend_creation_ms,graph_composition_ms,graph_finalization_ms"
    metrics_header="$metrics_header,graph_execution_ms,total_inference_ms"
    metrics_header="$metrics_header,ddr_spill_B,ddr_fill_B,ddr_write_total_B,ddr_read_total_B"
    
    # Create input times CSV header
    local input_times_header="model_name,backend,input_file,execution_time_ms"
    
    if echo "$metrics_header" > "$OUTPUT_METRICS_CSV"; then
        print_status "success" "Metrics CSV header created: $OUTPUT_METRICS_CSV"
    else
        print_status "error" "Failed to create metrics CSV file: $OUTPUT_METRICS_CSV"
        exit 1
    fi
    
    if echo "$input_times_header" > "$OUTPUT_INPUT_TIMES_CSV"; then
        print_status "success" "Input times CSV header created: $OUTPUT_INPUT_TIMES_CSV"
    else
        print_status "error" "Failed to create input times CSV file: $OUTPUT_INPUT_TIMES_CSV"
        exit 1
    fi
    
    if [ "$VERBOSE" = true ]; then
        print_status "info" "Metrics CSV columns (24 total):"
        echo "$metrics_header" | tr ',' '\n' | nl -w2 -s'. '
        echo
        print_status "info" "Input times CSV columns (4 total):"
        echo "$input_times_header" | tr ',' '\n' | nl -w2 -s'. '
    fi
}

run_batch_inference() {
    print_section_header "Batch Inference Execution"
    
    local models_count=$(jq '.models | length' "$CONFIG_FILE")
    print_status "info" "Starting batch inference for $models_count model(s)"
    print_status "info" "Continue on error mode: $CONTINUE_ON_ERROR"
    print_status "info" "Using device: $SELECTED_DEVICE"
    
    # Debug : show all models that will be processed
    if [ "$VERBOSE" = true ]; then
        echo
        print_status "info" "Models to process:"
        for debug_i in $(seq 0 $((models_count - 1))); do
            local debug_model_name=$(jq -r ".models[$debug_i].name // \"model_$debug_i\"" "$CONFIG_FILE")
            local debug_backend=$(jq -r ".models[$debug_i].backend" "$CONFIG_FILE")
            echo "  $((debug_i + 1)). $debug_model_name ($debug_backend)"
        done
        echo
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_status "info" "DRY RUN MODE - No actual inference will be performed"
    fi
    
    local successful_runs=0
    local failed_runs=0
    local all_run_ids=()
    local successful_models=()
    local failed_models=()
    
    for i in $(seq 0 $((models_count - 1))); do
        local model_name=$(jq -r ".models[$i].name // \"model_$i\"" "$CONFIG_FILE")
        
        echo
        echo "════════════════════════════════════════════════════════════════════"
        print_status "info" "Starting model $((i + 1))/$models_count: $model_name"
        echo "════════════════════════════════════════════════════════════════════"
        
        local run_id=""
        local run_success=false
        
        # Run single inference and capture result
        local inference_exit_code=0
        if run_single_inference "$i" "$models_count" "run_id"; then
            inference_exit_code=0
        else
            inference_exit_code=$?
        fi
        
        if [ $inference_exit_code -eq 0 ]; then
            run_success=true
            ((successful_runs++))
            successful_models+=("$model_name")
            if [ -n "$run_id" ]; then
                all_run_ids+=("$run_id")
            fi
            print_status "success" "Model $model_name completed successfully (Run ID: $run_id)"
        else
            run_success=false
            ((failed_runs++))
            failed_models+=("$model_name")
            print_status "error" "Model $model_name failed (exit code: $inference_exit_code)"
            
            # For failed runs, still add the run_id if it was generated
            if [ -n "$run_id" ]; then
                all_run_ids+=("$run_id")
            fi
            
            # Check if we should stop on error
            if [ "$CONTINUE_ON_ERROR" = false ]; then
                print_status "error" "Stopping batch execution due to error (run with -k to continue on errors)"
                break
            else
                print_status "info" "Continuing with next model..."
            fi
        fi
        
        echo "────────────────────────────────────────────────────────────────────"
        sleep 1
    done
    
    print_section_header "Batch Execution Summary"
    
    echo
    echo "Batch Results:"
    echo "=============="
    echo
    printf "  %-20s : %s\n" "Total Models" "$models_count"
    printf "  %-20s : %s\n" "Successful Runs" "$successful_runs"
    printf "  %-20s : %s\n" "Failed Runs" "$failed_runs"
    printf "  %-20s : %s\n" "Selected Device" "$SELECTED_DEVICE"
    printf "  %-20s : %s\n" "Continue on Error" "$CONTINUE_ON_ERROR"
    printf "  %-20s : %s\n" "Metrics CSV" "$OUTPUT_METRICS_CSV"
    printf "  %-20s : %s\n" "Input Times CSV" "$OUTPUT_INPUT_TIMES_CSV"
    
    if [ $failed_runs -gt 0 ]; then
        print_status "warning" "Some models failed during batch execution"
    else
        print_status "success" "All models completed successfully"
    fi
}

run_single_inference() {
    local model_index="$1"
    local total_models="$2"
    local -n run_id_ref="$3"  # Reference to return run_id
    
    # Extract model configuration
    local model_name=$(jq -r ".models[$model_index].name // \"model_$model_index\"" "$CONFIG_FILE")
    local file_path=$(jq -r ".models[$model_index].file_path" "$CONFIG_FILE")
    local backend=$(jq -r ".models[$model_index].backend" "$CONFIG_FILE")
    local run_count=$(jq -r ".models[$model_index].run_count // 1" "$CONFIG_FILE")
    local perf_profile=$(jq -r ".models[$model_index].perf_profile // \"balanced\"" "$CONFIG_FILE")
    local timeout=$(jq -r ".models[$model_index].timeout // 300" "$CONFIG_FILE")
    
    print_subsection "Model [$((model_index + 1))/$total_models]: $model_name"
    
    # Build inference command
    local inference_cmd="$SCRIPT_DIR/qnn_inference.sh"
    inference_cmd="$inference_cmd -m \"$file_path\""
    inference_cmd="$inference_cmd -b \"$backend\""
    inference_cmd="$inference_cmd -d \"$DATA_DIR\""
    inference_cmd="$inference_cmd -l \"$INPUT_LIST\""
    inference_cmd="$inference_cmd -n \"$run_count\""
    inference_cmd="$inference_cmd -p \"$perf_profile\""
    inference_cmd="$inference_cmd -t \"$timeout\""
    
    if [ "$VERBOSE" = true ]; then
        inference_cmd="$inference_cmd -v"
    fi
    
    print_status "info" "Configuration:"
    echo "  Model: $model_name"
    echo "  File: $file_path"
    echo "  Backend: $backend"
    echo "  Data Dir: $DATA_DIR"
    echo "  Input List: $INPUT_LIST"
    echo "  Performance: $perf_profile"
    echo "  Timeout: ${timeout}s"
    echo
    
    if [ "$DRY_RUN" = true ]; then
        print_status "info" "DRY RUN - Would execute:"
        echo "  $inference_cmd"
        echo
        return 0
    fi
    
    # Run inference
    print_status "info" "Running inference..."
    local inference_output
    local inference_result
    local run_id=""
    
    # Capture output and extract run ID
    inference_output=$(eval "$inference_cmd" 2>&1)
    inference_result=$?
    
    if [ "$VERBOSE" = true ]; then
        echo "Inference output:"
        echo "$inference_output"
        echo
    fi
    
    # Extract run ID from output
    run_id=$(echo "$inference_output" | grep -o "qnn_run_[0-9]*_[0-9]*" | tail -1)
    run_id_ref="$run_id"  # Return run_id to caller
    
    if [ $inference_result -eq 0 ] && [ -n "$run_id" ]; then
        print_status "success" "Inference completed successfully"
        print_status "info" "Run ID: $run_id"
    else
        print_status "error" "Inference failed with exit code: $inference_result"
        
        # Add error entry to CSV
        add_error_to_csv "$model_name" "$file_path" "$backend" "$perf_profile" "$run_id"
        
        if [ "$CONTINUE_ON_ERROR" = false ]; then
            return 1
        else
            return 1
        fi
    fi
    
    # Pull results using new pull script interface
    print_status "info" "Pulling results from device using new pull script..."
    
    # Find run number for our run_id on the selected device
    local run_number
    if run_number=$(find_run_number_from_run_id "$run_id" "$SELECTED_DEVICE"); then
        print_status "info" "Found run at position $run_number on device"
    else
        print_status "error" "Run $run_id not found on device $SELECTED_DEVICE"
        add_error_to_csv "$model_name" "$file_path" "$backend" "$perf_profile" "$run_id"
        
        if [ "$CONTINUE_ON_ERROR" = false ]; then
            return 1
        else
            return 1
        fi
    fi
    
    # Call new pull script with device selection automated and run number
    local pull_cmd="echo \"$SELECTED_DEVICE_NUMBER\" | $SCRIPT_DIR/qnn_pull.sh $run_number -f"
    
    if [ "$VERBOSE" = true ]; then
        pull_cmd="echo \"$SELECTED_DEVICE_NUMBER\" | $SCRIPT_DIR/qnn_pull.sh $run_number -f -v"
    fi
    
    local pull_output
    local pull_result
    
    print_status "info" "Executing pull command for run #$run_number..."
    pull_output=$(eval "$pull_cmd" 2>&1)
    pull_result=$?
    
    if [ "$VERBOSE" = true ]; then
        echo "Pull output:"
        echo "$pull_output"
        echo
    fi
    
    if [ $pull_result -eq 0 ]; then
        print_status "success" "Results pulled successfully"
        
        # Extract metrics using extract_metrics.sh
        if extract_and_process_metrics "$model_name" "$file_path" "$backend" "$perf_profile" "$run_id"; then
            print_status "success" "Metrics processed for $model_name"
        else
            print_status "error" "Failed to process metrics for $model_name"
            add_error_to_csv "$model_name" "$file_path" "$backend" "$perf_profile" "$run_id"
            
            if [ "$CONTINUE_ON_ERROR" = false ]; then
                return 1
            else
                return 1
            fi
        fi
        
        # Cleanup run directory if requested
        if [ "$CLEANUP_RUNS" = true ]; then
            cleanup_run_directory "$run_id"
        fi
        
    else
        print_status "error" "Failed to pull results (exit code: $pull_result)"
        add_error_to_csv "$model_name" "$file_path" "$backend" "$perf_profile" "$run_id"
        
        if [ "$CONTINUE_ON_ERROR" = false ]; then
            return 1
        else
            return 1
        fi
    fi
    
    return 0
}

extract_and_process_metrics() {
    local model_name="$1"
    local file_path="$2"
    local backend="$3"
    local perf_profile="$4"
    local run_id="$5"
    
    print_status "info" "Extracting metrics for $model_name using extract_metrics.sh..."
    
    # Run extract_metrics.sh to process the QNN output and populate CSV
    local extract_cmd="$SCRIPT_DIR/extract_metrics.sh \"$run_id\""
    
    if [ "$VERBOSE" = true ]; then
        extract_cmd="$extract_cmd -v"
    fi
    
    local extract_output
    local extract_result
    
    extract_output=$(eval "$extract_cmd" 2>&1)
    extract_result=$?
    
    if [ "$VERBOSE" = true ]; then
        echo "Extract output:"
        echo "$extract_output"
        echo
    fi
    
    if [ $extract_result -eq 0 ]; then
        print_status "success" "Metrics extraction completed"
        
        # Now compile the processed CSV into batch formats
        if compile_metrics_to_batch_csv "$model_name" "$backend" "$run_id" && \
           compile_input_times_to_batch_csv "$model_name" "$backend" "$run_id"; then
            return 0
        else
            return 1
        fi
    else
        print_status "error" "Metrics extraction failed"
        return 1
    fi
}

compile_metrics_to_batch_csv() {
    local model_name="$1"
    local backend="$2"
    local run_id="$3"
    
    print_status "info" "Compiling metrics to batch CSV for $model_name"
    
    local run_metrics_csv="$PROJECT_ROOT/outputs/$run_id/metrics/metrics.csv"
    
    if [ ! -f "$run_metrics_csv" ]; then
        print_status "error" "No metrics CSV found for run: $run_id"
        return 1
    fi
    
    # Read the metrics CSV (should have exactly 2 lines: header + data)
    local csv_content=$(cat "$run_metrics_csv")
    local header_line=$(echo "$csv_content" | head -1)
    local data_line=$(echo "$csv_content" | tail -1)
    
    if [ "$data_line" = "$header_line" ]; then
        print_status "warning" "Metrics CSV contains only header, no data"
        return 1
    fi
    
    if echo "$data_line" >> "$OUTPUT_METRICS_CSV"; then
        print_status "success" "Metrics row added to batch CSV"
        
        if [ "$VERBOSE" = true ]; then
            # Parse some key values for display
            local success=$(echo "$data_line" | cut -d',' -f7)
            local total_time=$(echo "$data_line" | cut -d',' -f8)
            local avg_inference_time=$(echo "$data_line" | cut -d',' -f15)
            echo "  Success: $success"
            echo "  Total time: ${total_time}s"
            echo "  Avg inference: ${avg_inference_time}ms"
        fi
        
        return 0
    else
        print_status "error" "Failed to write to batch metrics CSV"
        return 1
    fi
}

compile_input_times_to_batch_csv() {
    local model_name="$1"
    local backend="$2"
    local run_id="$3"
    
    print_status "info" "Compiling input times to batch CSV for $model_name"
    
    local input_times_csv="$PROJECT_ROOT/outputs/$run_id/metrics/input_times.csv"
    
    if [ ! -f "$input_times_csv" ]; then
        print_status "error" "No input times CSV found for run: $run_id"
        return 1
    fi
    
    # Read the input times CSV and add model info to each row
    local line_count=0
    while IFS=',' read -r input_file execution_time; do
        # Skip header line
        if [ $line_count -eq 0 ]; then
            ((line_count++))
            continue
        fi
        
        # Create batch format: model_name,backend,input_file,execution_time_ms
        local batch_row="\"$model_name\",\"$backend\",\"$input_file\",$execution_time"
        
        if echo "$batch_row" >> "$OUTPUT_INPUT_TIMES_CSV"; then
            [ "$VERBOSE" = true ] && echo "  Added: $input_file -> ${execution_time}ms"
        else
            print_status "error" "Failed to write input time row"
            return 1
        fi
        
        ((line_count++))
    done < "$input_times_csv"
    
    print_status "success" "Added $((line_count-1)) input time entries for $model_name"
    return 0
}

add_error_to_csv() {
    local model_name="$1"
    local file_path="$2"
    local backend="$3"
    local perf_profile="$4"
    local run_id="$5"
    
    local timestamp="$(date -Iseconds)"
    
    # Create error row with all fields set to default/error values
    local csv_row="$timestamp,\"$run_id\",\"$model_name\",\"$backend\",\"$SELECTED_DEVICE\",\"$perf_profile\",false,0,0"
    csv_row="$csv_row,0,input_0,0,input_0,0,0,0,0,0,0,0,0,0,0,0"
    
    if echo "$csv_row" >> "$OUTPUT_METRICS_CSV"; then
        print_status "warning" "Error entry added to metrics CSV for $model_name"
        return 0
    else
        print_status "error" "Failed to add error entry to metrics CSV for $model_name"
        return 1
    fi
}

cleanup_run_directory() {
    local run_id="$1"
    
    if [ -z "$run_id" ]; then
        return 0
    fi
    
    local run_dir="$PROJECT_ROOT/outputs/$run_id"
    
    if [ -d "$run_dir" ]; then
        print_status "info" "Cleaning up run directory: $run_dir"
        rm -rf "$run_dir"
        print_status "success" "Run directory cleaned up"
    fi
}

display_final_summary() {
    print_section_header "Final Summary"
    
    if [ "$DRY_RUN" = true ]; then
        print_status "info" "DRY RUN completed - no actual inference was performed"
        return 0
    fi
    
    print_status "success" "Enhanced batch inference execution completed!"
    echo
    
    # Display CSV info
    if [ -f "$OUTPUT_METRICS_CSV" ] && [ -f "$OUTPUT_INPUT_TIMES_CSV" ]; then
        local metrics_lines=$(wc -l < "$OUTPUT_METRICS_CSV")
        local metrics_data_lines=$((metrics_lines - 1))
        local metrics_size=$(ls -lh "$OUTPUT_METRICS_CSV" | awk '{print $5}')
        
        local input_times_lines=$(wc -l < "$OUTPUT_INPUT_TIMES_CSV")
        local input_times_data_lines=$((input_times_lines - 1))
        local input_times_size=$(ls -lh "$OUTPUT_INPUT_TIMES_CSV" | awk '{print $5}')
        
        local models_count=$(jq '.models | length' "$CONFIG_FILE")
        
        print_status "info" "Results compiled into batch CSV files:"
        echo
        echo "Metrics CSV:"
        echo "-----------"
        printf "  %-15s : %s\n" "File" "$OUTPUT_METRICS_CSV"
        printf "  %-15s : %s / %s expected\n" "Data rows" "$metrics_data_lines" "$models_count"
        printf "  %-15s : %s\n" "Columns" "24 (new format)"
        printf "  %-15s : %s\n" "Size" "$metrics_size"
        printf "  %-15s : %s\n" "Device Used" "$SELECTED_DEVICE"
        echo
        echo "Input Times CSV:"
        echo "---------------"
        printf "  %-15s : %s\n" "File" "$OUTPUT_INPUT_TIMES_CSV"
        printf "  %-15s : %s individual timings\n" "Data rows" "$input_times_data_lines"
        printf "  %-15s : %s\n" "Columns" "4 (model, backend, input, time)"
        printf "  %-15s : %s\n" "Size" "$input_times_size"
        
        if [ "$metrics_data_lines" -eq "$models_count" ]; then
            print_status "success" "✓ All models are represented in the metrics CSV"
        else
            print_status "warning" "⚠ Metrics CSV has $metrics_data_lines rows but expected $models_count"
        fi
    fi
    
    echo
    print_status "info" "Analysis Commands:"
    echo
    echo "Useful Commands:"
    echo "---------------"
    printf "  %-25s : %s\n" "View metrics CSV" "column -t -s, $OUTPUT_METRICS_CSV | less -S"
    printf "  %-25s : %s\n" "View input times CSV" "column -t -s, $OUTPUT_INPUT_TIMES_CSV | less -S"
    printf "  %-25s : %s\n" "Count successes" "grep -c ',true,' $OUTPUT_METRICS_CSV"
    printf "  %-25s : %s\n" "List failed models" "grep ',false,' $OUTPUT_METRICS_CSV | cut -d, -f3"
    printf "  %-25s : %s\n" "Open in spreadsheet" "libreoffice $OUTPUT_METRICS_CSV"
    
    echo
    print_status "info" "Metrics Summary:"
    echo "  • Each model tested with same data: $DATA_DIR"
    echo "  • Each model used same input list: $INPUT_LIST"
    echo "  • All runs executed on device: $SELECTED_DEVICE"
    echo "  • Metrics extracted using extract_metrics.sh automatically"
    echo "  • All timing data compiled into standardized format"
    echo "  • Individual input execution times tracked per model"
    
    echo
    print_status "success" "Batch inference completed! Use CSV files for performance analysis."
}

main() {
    # Handle cleanup on exit
    trap 'echo; print_status "info" "Batch inference interrupted"' INT TERM
    
    echo
    echo "╔════════════════════════════════════════╗"
    echo "║       Batch QNN Inference Runner       ║"
    echo "╚════════════════════════════════════════╝"
    
    parse_arguments "$@"
    setup_environment
    validate_config
    
    # Device selection
    if [ "$DRY_RUN" = false ]; then
        select_device_for_batch || exit 1
        initialize_csv_files
    fi
    
    run_batch_inference
    display_final_summary
    
    exit 0
}

main "$@"

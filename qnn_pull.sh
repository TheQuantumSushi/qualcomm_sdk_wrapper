#!/bin/bash

# QNN Pull - Pull QNN run results from connected Android devices

# Colors
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
NC='\033[0m'

# Configuration
DEVICE_TMPDIR="/data/local/tmp"
QNN_RUN_PREFIX="qnn_run_"
VERBOSE=false

# Get project root
if [ -z "$PROJECT_ROOT" ]; then
    if [ -f "config.json" ] && command -v jq &> /dev/null; then
        PROJECT_NAME=$(jq -r '.names.project' config.json 2>/dev/null)
        if [ "$PROJECT_NAME" != "null" ] && [ -n "$PROJECT_NAME" ]; then
            if [ -n "$QUALCOMM_ROOT" ]; then
                PROJECT_ROOT="$QUALCOMM_ROOT/projects/$PROJECT_NAME"
            else
                PROJECT_ROOT="../projects/$PROJECT_NAME"
            fi
        fi
    fi
    
    if [ -z "$PROJECT_ROOT" ]; then
        echo -e "${RED}⚠ PROJECT_ROOT not set${NC}"
        exit 1
    fi
fi

OUTPUTS_DIR="$PROJECT_ROOT/outputs"

show_help() {
    cat << EOF

${BLUE}QNN Pull - Results Retrieval Tool${NC}
${BLUE}==================================${NC}

${GREEN}DESCRIPTION:${NC}
    Pulls QNN inference results from connected Android devices and processes them
    with extract_metrics.sh to generate complete performance metrics. Manages
    QNN run directories on device with pull and cleanup operations.

${GREEN}USAGE:${NC}
    $0 [COMMAND] [RUN_NUMBERS...] [OPTIONS]

${GREEN}COMMANDS:${NC}
    ${YELLOW}pull${NC}                Pull run results to local PROJECT_ROOT/outputs/ (default)
    ${YELLOW}clean${NC}               Delete run directories from device

${GREEN}ARGUMENTS:${NC}
    ${YELLOW}RUN_NUMBERS${NC}         Space-separated list of run numbers to process (e.g., 1 3 5)

${GREEN}OPTIONS:${NC}
    ${YELLOW}-l, --list${NC}          List available QNN runs on device and exit
    ${YELLOW}-a, --all${NC}           Process all available runs
    ${YELLOW}-f, --force${NC}         Force operation without confirmation prompts
    ${YELLOW}-v, --verbose${NC}       Enable verbose output showing detailed progress
    ${YELLOW}-h, --help${NC}          Show this help message

${GREEN}EXAMPLES:${NC}
    # List available runs on device
    $0 -l

    # Pull specific runs (1, 3, and 5)
    $0 1 3 5

    # Pull all available runs
    $0 pull -a

    # Clean specific runs from device
    $0 clean 2 4

    # Clean all runs from device (with confirmation)
    $0 clean -a

    # Force pull run 1 without prompts, verbose output
    $0 pull 1 -f -v

${GREEN}DEVICE OPERATIONS:${NC}
    ${YELLOW}Device Selection:${NC}     Interactive selection if multiple devices connected
    ${YELLOW}Run Detection:${NC}       Scans /data/local/tmp/ for qnn_run_* directories
    ${YELLOW}File Transfer:${NC}       Uses ADB to pull results, metrics, and logs
    ${YELLOW}Auto-Processing:${NC}     Calls extract_metrics.sh automatically after pull

${GREEN}RUN DIRECTORY STRUCTURE:${NC}
    Device: /data/local/tmp/qnn_run_YYYYMMDD_HHMMSS/
    ├── results/        # Inference output files (.raw, .bin)
    ├── metrics/        # Initial CSV and QNN logs
    └── [excluded: data/, model/, run_inference.sh]

    Local: PROJECT_ROOT/outputs/qnn_run_YYYYMMDD_HHMMSS/
    ├── results/        # Pulled inference results
    └── metrics/        # Complete metrics with extract_metrics.sh output

${GREEN}PULL WORKFLOW:${NC}
    1. Device selection (if multiple available)
    2. List and select QNN runs to retrieve
    3. Pull run directories to PROJECT_ROOT/outputs/
    4. Automatically call extract_metrics.sh for each run
    5. Generate complete performance metrics and CSV files

${GREEN}CLEAN WORKFLOW:${NC}
    1. Device selection
    2. Confirmation prompt (unless -f used)
    3. Delete specified run directories from device
    4. Free up device storage space

${GREEN}OUTPUT FILES:${NC}
    For each pulled run in PROJECT_ROOT/outputs/qnn_run_*/metrics/:
    • metrics.csv        - Complete 24-column performance metrics
    • input_times.csv    - Individual input execution times
    • qnn_output.txt     - Original QNN inference logs
    • device_info.txt    - Device information

${GREEN}INTEGRATION:${NC}
    Part of the QNN inference pipeline:
    qnn_inference.sh → ${YELLOW}qnn_pull.sh${NC} → extract_metrics.sh → batch_inference.sh

    Automatically called by batch_inference.sh for multi-model testing.

${GREEN}REQUIREMENTS:${NC}
    • PROJECT_ROOT environment variable or config.json with project name
    • Connected Android device with QNN runs in /data/local/tmp/
    • ADB installed and device accessible
    • extract_metrics.sh available in same directory
    • Sufficient local storage for results

${GREEN}DEVICE REQUIREMENTS:${NC}
    • Android device with ADB debugging enabled
    • QNN runs created by qnn_inference.sh
    • Accessible /data/local/tmp/ directory

EOF
}

check_adb() {
    if ! command -v adb &> /dev/null; then
        echo -e "${RED}⚠ ADB not found${NC}"
        return 1
    fi
    return 0
}

select_device() {
    echo "Checking devices..."
    local devices=($(adb devices | grep -E "\s+device$" | cut -f1))
    
    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${RED}⚠ No devices found${NC}"
        return 1
    fi
    
    echo
    echo "Available devices:"
    for i in "${!devices[@]}"; do
        echo "  $((i+1)). ${devices[$i]}"
    done
    
    echo
    while true; do
        read -p "Select device (1-${#devices[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#devices[@]} ]; then
            SELECTED_DEVICE="${devices[$((choice-1))]}"
            return 0
        fi
        echo -e "${RED}Invalid selection${NC}"
    done
}

get_qnn_runs() {
    local device_id="$1"
    adb -s "$device_id" shell "ls -1 $DEVICE_TMPDIR 2>/dev/null | grep '^${QNN_RUN_PREFIX}'" 2>/dev/null | tr -d '\r'
}

get_stats() {
    local device_id="$1"
    local folder_path="$2"
    
    # Get items excluding data, model, run_inference.sh
    local items=$(adb -s "$device_id" shell "ls -1 '$folder_path' 2>/dev/null" | tr -d '\r' | grep -v '^data$' | grep -v '^model$' | grep -v '^run_inference.sh$')
    
    if [ -z "$items" ]; then
        echo "0:0"
        return
    fi
    
    local total_files=0
    local total_size=0
    
    for item in $items; do
        if [ -n "$item" ]; then
            local files=$(adb -s "$device_id" shell "find '$folder_path/$item' -type f 2>/dev/null | wc -l" | tr -d '\r')
            local size=$(adb -s "$device_id" shell "du -sk '$folder_path/$item' 2>/dev/null | cut -f1" | tr -d '\r')
            
            if [[ "$files" =~ ^[0-9]+$ ]]; then
                total_files=$((total_files + files))
            fi
            if [[ "$size" =~ ^[0-9]+$ ]]; then
                total_size=$((total_size + size))
            fi
        fi
    done
    
    echo "$total_files:$total_size"
}

format_size() {
    local kb="$1"
    if [[ ! "$kb" =~ ^[0-9]+$ ]] || [ "$kb" -eq 0 ]; then
        echo "0 B"
    elif [ "$kb" -lt 1024 ]; then
        echo "${kb} KB"
    else
        echo "$((kb / 1024)) MB"
    fi
}

list_runs() {
    local device_id="$1"
    local runs=($(get_qnn_runs "$device_id"))
    
    if [ ${#runs[@]} -eq 0 ]; then
        echo -e "${RED}⚠ No QNN runs found${NC}"
        return 1
    fi
    
    echo
    echo "QNN runs on device:"
    echo "==================="
    echo
    
    for i in "${!runs[@]}"; do
        local run="${runs[$i]}"
        echo -n "  $((i+1)). $run"
        
        local stats=$(get_stats "$device_id" "$DEVICE_TMPDIR/$run")
        local files=$(echo "$stats" | cut -d: -f1)
        local size=$(echo "$stats" | cut -d: -f2)
        
        echo
        echo -e "      Files: ${GREEN}$files${NC} | Size: ${GREEN}$(format_size $size)${NC}"
        echo
    done
    
    return 0
}

pull_run() {
    local device_id="$1"
    local run_folder="$2"
    local local_path="$3"
    
    mkdir -p "$local_path" || return 1
    
    local items=$(adb -s "$device_id" shell "ls -1 '$DEVICE_TMPDIR/$run_folder' 2>/dev/null" | tr -d '\r' | grep -v '^data$' | grep -v '^model$' | grep -v '^run_inference.sh$')
    
    if [ -z "$items" ]; then
        echo -e "      ${YELLOW}⚠${NC} No items to pull"
        return 0
    fi
    
    for item in $items; do
        if [ -n "$item" ]; then
            if [ "$VERBOSE" = true ]; then
                echo "        - $item"
                adb -s "$device_id" pull "$DEVICE_TMPDIR/$run_folder/$item" "$local_path/"
            else
                adb -s "$device_id" pull "$DEVICE_TMPDIR/$run_folder/$item" "$local_path/" &>/dev/null
            fi
        fi
    done
    
    echo -e "      ${GREEN}✔${NC} Pull completed"
    return 0
}

pull_runs() {
    local device_id="$1"
    shift
    local run_numbers=("$@")
    
    local runs=($(get_qnn_runs "$device_id"))
    
    mkdir -p "$OUTPUTS_DIR" || return 1
    
    echo
    echo "Pulling QNN runs:"
    echo "================="
    echo
    
    for run_num in "${run_numbers[@]}"; do
        if [[ ! "$run_num" =~ ^[0-9]+$ ]] || [ "$run_num" -lt 1 ] || [ "$run_num" -gt ${#runs[@]} ]; then
            echo -e "${RED}⚠ Invalid run number: $run_num${NC}"
            continue
        fi
        
        local run_folder="${runs[$((run_num-1))]}"
        local local_path="$OUTPUTS_DIR/$run_folder"
        
        echo "  $run_num. $run_folder"
        
        if [ -d "$local_path" ]; then
            if [ "$FORCE" = true ]; then
                rm -rf "$local_path"
            else
                read -p "      Directory exists. Overwrite? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo -e "      ${YELLOW}⚠${NC} Skipping"
                    continue
                fi
                rm -rf "$local_path"
            fi
        fi
        
        pull_run "$device_id" "$run_folder" "$local_path"
        echo
    done
}

clean_run() {
    local device_id="$1"
    local run_folder="$2"
    
    adb -s "$device_id" shell "rm -rf '$DEVICE_TMPDIR/$run_folder'" &>/dev/null
    echo -e "      ${GREEN}✔${NC} Deleted"
}

clean_runs() {
    local device_id="$1"
    shift
    local run_numbers=("$@")
    
    local runs=($(get_qnn_runs "$device_id"))
    
    echo
    echo "Cleaning QNN runs:"
    echo "=================="
    echo
    
    echo -e "${YELLOW}⚠ WARNING: This will delete runs permanently!${NC}"
    if [ "$FORCE" = false ]; then
        read -p "Continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled"
            return 0
        fi
    fi
    echo
    
    for run_num in "${run_numbers[@]}"; do
        if [[ ! "$run_num" =~ ^[0-9]+$ ]] || [ "$run_num" -lt 1 ] || [ "$run_num" -gt ${#runs[@]} ]; then
            echo -e "${RED}⚠ Invalid run number: $run_num${NC}"
            continue
        fi
        
        local run_folder="${runs[$((run_num-1))]}"
        echo "  $run_num. $run_folder"
        clean_run "$device_id" "$run_folder"
        echo
    done
}

# Parse arguments
LIST_ONLY=false
FORCE=false
ALL_RUNS=false
COMMAND=""
RUN_NUMBERS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -a|--all)
            ALL_RUNS=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        clean)
            COMMAND="clean"
            shift
            ;;
        pull)
            COMMAND="pull"
            shift
            ;;
        -*)
            echo -e "${RED}⚠ Unknown option: $1${NC}"
            exit 1
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                RUN_NUMBERS+=("$1")
            else
                echo -e "${RED}⚠ Invalid run number: $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# Default command
if [ -z "$COMMAND" ] && [ "$LIST_ONLY" = false ]; then
    COMMAND="pull"
fi

# Check ADB
if ! check_adb; then
    exit 1
fi

# Select device
echo
echo "QNN Pull - Device Setup"
echo "======================="

select_device || exit 1

echo -e "# ${GREEN}✔${NC} Selected device: $SELECTED_DEVICE"

# List runs
if [ "$LIST_ONLY" = true ]; then
    list_runs "$SELECTED_DEVICE"
    exit $?
fi

# Handle -a flag
if [ "$ALL_RUNS" = true ]; then
    runs=($(get_qnn_runs "$SELECTED_DEVICE"))
    if [ ${#runs[@]} -eq 0 ]; then
        echo -e "${RED}⚠ No QNN runs found${NC}"
        exit 1
    fi
    
    RUN_NUMBERS=()
    for i in $(seq 1 ${#runs[@]}); do
        RUN_NUMBERS+=("$i")
    done
    
    echo "Processing all ${#RUN_NUMBERS[@]} runs..."
fi

# Check run numbers
if [ ${#RUN_NUMBERS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠ No run numbers specified${NC}"
    echo "Use -l to list runs, -a for all"
    exit 1
fi

# Execute command
case "$COMMAND" in
    "pull")
        pull_runs "$SELECTED_DEVICE" "${RUN_NUMBERS[@]}"
        echo -e "# ${GREEN}✔${NC} Pull completed"
        ;;
    "clean")
        clean_runs "$SELECTED_DEVICE" "${RUN_NUMBERS[@]}"
        echo -e "# ${GREEN}✔${NC} Clean completed"
        ;;
esac

echo
echo "----- QNN Pull completed -----"

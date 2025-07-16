#!/bin/bash

# Extract QNN Metrics - Parse QNN output and update metrics CSV
# Part of the Qualcomm AI Hub toolkit

### PARAMETERS : ###

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
BLUE='\033[38;2;0;123;255m'
NC='\033[0m' # no color

# Configuration :
VERBOSE=false
QNN_OUTPUT_FILE=""
METRICS_CSV=""
WORK_DIR=""

# Global variables for metrics
MIN_EXEC_TIME=0
MIN_EXEC_FILE=""
MAX_EXEC_TIME=0
MAX_EXEC_FILE=""
MEDIAN_EXEC_TIME=0
AVG_EXEC_TIME=0
BACKEND_CREATION_TIME=0
GRAPH_COMPOSITION_TIME=0
GRAPH_FINALIZATION_TIME=0
GRAPH_EXECUTION_TIME=0
TOTAL_INFERENCE_TIME=0
DDR_SPILL_B=0
DDR_FILL_B=0
DDR_WRITE_TOTAL_B=0
DDR_READ_TOTAL_B=0

### FUNCTIONS : ###

show_help() {
    cat << EOF

${BLUE}QNN Metrics Extraction Tool${NC}
${BLUE}============================${NC}

${GREEN}DESCRIPTION:${NC}
    Extracts detailed timing and performance metrics from QNN inference output
    and populates CSV files with comprehensive statistics. Part of the QNN
    inference pipeline - typically called automatically by qnn_pull.sh.

${GREEN}USAGE:${NC}
    $0 QNN_RUN_FOLDER [OPTIONS]

${GREEN}REQUIRED ARGUMENTS:${NC}
    ${YELLOW}QNN_RUN_FOLDER${NC}       QNN run directory name (e.g., qnn_run_20250715_143022)

${GREEN}OPTIONAL ARGUMENTS:${NC}
    ${YELLOW}-v, --verbose${NC}        Enable verbose output showing detailed parsing
    ${YELLOW}-h, --help${NC}           Show this help message

${GREEN}INPUT FILES:${NC}
    Required files in PROJECT_ROOT/outputs/QNN_RUN_FOLDER/metrics/:
    • qnn_output.txt     - QNN inference log output
    • metrics.csv        - Initial metrics CSV with basic structure

${GREEN}OUTPUT FILES:${NC}
    Updates and creates in the same metrics/ directory:
    • metrics.csv        - Updated with 24 columns of performance data
    • input_times.csv    - Individual input file execution times

${GREEN}EXTRACTED METRICS:${NC}
    ${YELLOW}Execution Statistics:${NC}
    • Minimum/maximum unit inference times with filenames
    • Median and average inference times
    • Individual input execution times

    ${YELLOW}QNN Timing Breakdown:${NC}
    • Backend creation time
    • Graph composition and finalization times
    • Graph execution time
    • Total inference time

    ${YELLOW}Memory Metrics (HTP):${NC}
    • DDR bandwidth statistics (spill, fill, read, write)
    • Memory usage patterns

${GREEN}EXAMPLES:${NC}
    # Extract metrics from specific run
    $0 qnn_run_20250715_143022

    # Verbose extraction with detailed parsing output
    $0 qnn_run_20250715_143022 -v

    # Typically called automatically by pull script
    ./qnn_pull.sh 1  # This calls extract_metrics.sh internally

${GREEN}CSV OUTPUT FORMAT:${NC}
    ${YELLOW}metrics.csv (24 columns):${NC}
    timestamp, run_id, model, backend, device, perf_profile, success,
    total_time_seconds, output_files_count, minimum_unit_inference_time_ms,
    minimum_unit_inference_file, maximum_unit_inference_time_ms,
    maximum_unit_inference_file, median_unit_inference_time_ms,
    average_unit_inference_time_ms, backend_creation_ms, graph_composition_ms,
    graph_finalization_ms, graph_execution_ms, total_inference_ms,
    ddr_spill_B, ddr_fill_B, ddr_write_total_B, ddr_read_total_B

    ${YELLOW}input_times.csv (4 columns):${NC}
    input_file, execution_time_ms

${GREEN}REQUIREMENTS:${NC}
    • PROJECT_ROOT environment variable or config.json with project name
    • Valid QNN run directory with qnn_output.txt and initial metrics.csv
    • awk for floating-point calculations

${GREEN}INTEGRATION:${NC}
    This script is part of the QNN inference pipeline:
    qnn_inference.sh → qnn_pull.sh → extract_metrics.sh → batch_inference.sh

EOF
}

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "success") echo -e "${GREEN}✔${NC} $message" ;;
        "error") echo -e "${RED}✗${NC} $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} $message" ;;
        "info") echo -e "${BLUE}ℹ${NC} $message" ;;
    esac
}

setup_environment() {
    print_status "info" "Setting up environment"
    
    # Get project root from environment or config
    if [ -z "$PROJECT_ROOT" ]; then
        if [ -f "config.json" ] && command -v jq &> /dev/null; then
            local project_name=$(jq -r '.names.project' config.json 2>/dev/null)
            if [ "$project_name" != "null" ] && [ -n "$project_name" ]; then
                if [ -n "$QUALCOMM_ROOT" ]; then
                    PROJECT_ROOT="$QUALCOMM_ROOT/projects/$project_name"
                else
                    PROJECT_ROOT="../projects/$project_name"
                fi
            fi
        fi
        
        if [ -z "$PROJECT_ROOT" ]; then
            print_status "error" "PROJECT_ROOT not set and could not determine from config.json"
            exit 1
        fi
    fi
    
    print_status "success" "Environment configured"
}

validate_inputs() {
    local qnn_run_folder="$1"
    
    print_status "info" "Validating inputs"
    
    if [ -z "$qnn_run_folder" ]; then
        print_status "error" "QNN run folder not specified"
        show_help
        exit 1
    fi
    
    WORK_DIR="$PROJECT_ROOT/outputs/$qnn_run_folder/metrics"
    QNN_OUTPUT_FILE="$WORK_DIR/qnn_output.txt"
    METRICS_CSV="$WORK_DIR/metrics.csv"
    
    if [ ! -d "$WORK_DIR" ]; then
        print_status "error" "Metrics directory not found: $WORK_DIR"
        exit 1
    fi
    
    if [ ! -f "$QNN_OUTPUT_FILE" ]; then
        print_status "error" "QNN output file not found: $QNN_OUTPUT_FILE"
        exit 1
    fi
    
    if [ ! -f "$METRICS_CSV" ]; then
        print_status "error" "Metrics CSV not found: $METRICS_CSV"
        exit 1
    fi
    
    print_status "success" "All inputs validated"
}

clean_timestamp() {
    local timestamp="$1"
    # Remove carriage returns and any non-numeric/decimal characters except the dot
    echo "$timestamp" | tr -d '\r\n' | sed 's/[^0-9.]//g'
}

safe_calculate() {
    local expr="$1"
    local result
    
    # Use awk for floating point calculation instead of bc to avoid syntax issues
    result=$(echo "$expr" | awk '{print $3 - $1}' 2>/dev/null)
    
    # Validate result
    if [[ "$result" =~ ^[0-9]+\.?[0-9]*$ ]] && [ $(echo "$result >= 0" | awk '{print ($1 >= 0)}') -eq 1 ]; then
        echo "$result"
    else
        echo "0"
    fi
}

extract_execution_times() {
    print_status "info" "Extracting individual execution times"
    
    local temp_times="/tmp/execution_times_$$.txt"
    local temp_clean="/tmp/qnn_clean_$$.txt"
    
    # Clean the input file of carriage returns and problematic characters
    tr -d '\r' < "$QNN_OUTPUT_FILE" > "$temp_clean"
    
    # Extract QnnGraph_execute start and done times with improved regex
    local start_pattern="QnnGraph_execute started"
    local end_pattern="QnnGraph_execute done"
    
    # Get all start times
    local start_times_raw=($(grep "$start_pattern" "$temp_clean" | sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/'))
    local end_times_raw=($(grep "$end_pattern" "$temp_clean" | sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/'))
    
    # Clean timestamps
    local start_times=()
    local end_times=()
    
    for time in "${start_times_raw[@]}"; do
        local clean_time=$(clean_timestamp "$time")
        if [[ "$clean_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            start_times+=("$clean_time")
        fi
    done
    
    for time in "${end_times_raw[@]}"; do
        local clean_time=$(clean_timestamp "$time")
        if [[ "$clean_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            end_times+=("$clean_time")
        fi
    done
    
    if [ ${#start_times[@]} -ne ${#end_times[@]} ]; then
        print_status "warning" "Mismatch in start/end execution times (${#start_times[@]}/${#end_times[@]})"
    fi
    
    local execution_times=()
    local min_count=${#start_times[@]}
    if [ ${#end_times[@]} -lt $min_count ]; then
        min_count=${#end_times[@]}
    fi
    
    # Calculate execution times for each input
    for ((i=0; i<min_count; i++)); do
        local start_time=${start_times[$i]}
        local end_time=${end_times[$i]}
        
        # Use awk for calculation
        local exec_time=$(awk "BEGIN {print $end_time - $start_time}")
        
        # Validate result
        if [[ "$exec_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [ $(awk "BEGIN {print ($exec_time >= 0)}") -eq 1 ]; then
            execution_times+=("$exec_time")
            echo "input_$((i+1)),$exec_time" >> "$temp_times"
            [ "$VERBOSE" = true ] && print_status "info" "Input $((i+1)): ${exec_time}ms"
        else
            print_status "warning" "Invalid execution time calculated for input $((i+1))"
        fi
    done
    
    print_status "success" "Extracted ${#execution_times[@]} execution times"
    
    # Calculate statistics using awk for better precision
    if [ ${#execution_times[@]} -gt 0 ]; then
        # Create temp file with input names and times for tracking min/max files
        local temp_with_names="/tmp/times_with_names_$.txt"
        for ((i=0; i<${#execution_times[@]}; i++)); do
            echo "input_$((i+1)) ${execution_times[$i]}" >> "$temp_with_names"
        done
        
        # Calculate min, max, sum, count and track filenames
        local stats=$(awk '
            BEGIN { min=999999; max=0; sum=0; count=0; min_file=""; max_file="" }
            {
                time = $2
                file = $1
                if (time < min) { min = time; min_file = file }
                if (time > max) { max = time; max_file = file }
                sum += time
                count++
                times[count] = time
            }
            END {
                # Sort for median
                n = asort(times)
                if (n % 2 == 0) {
                    median = (times[n/2] + times[n/2+1]) / 2
                } else {
                    median = times[(n+1)/2]
                }
                avg = sum / count
                printf "%.2f %s %.2f %s %.2f %.2f", min, min_file, max, max_file, median, avg
            }
        ' "$temp_with_names")
        
        read MIN_EXEC_TIME MIN_EXEC_FILE MAX_EXEC_TIME MAX_EXEC_FILE MEDIAN_EXEC_TIME AVG_EXEC_TIME <<< "$stats"
        
        rm -f "$temp_with_names"
        
        [ "$VERBOSE" = true ] && {
            print_status "info" "Statistics: Min=${MIN_EXEC_TIME}ms (${MIN_EXEC_FILE}), Max=${MAX_EXEC_TIME}ms (${MAX_EXEC_FILE})"
            print_status "info" "           Med=${MEDIAN_EXEC_TIME}ms, Avg=${AVG_EXEC_TIME}ms"
        }
    else
        print_status "error" "No execution times found"
        rm -f "$temp_clean" "$temp_times"
        exit 1
    fi
    
    # Create input_times CSV
    create_input_times_csv "$temp_times"
    rm -f "$temp_clean" "$temp_times"
}

create_input_times_csv() {
    local temp_times="$1"
    local input_times_csv="$WORK_DIR/input_times.csv"
    
    print_status "info" "Creating input times CSV"
    
    # Create header
    echo "input_file,execution_time_ms" > "$input_times_csv"
    
    # Add data
    if [ -f "$temp_times" ]; then
        cat "$temp_times" >> "$input_times_csv"
        print_status "success" "Input times CSV created: input_times.csv"
    else
        print_status "warning" "No input times data to write"
    fi
}

extract_single_time_diff() {
    local start_pattern="$1"
    local end_pattern="$2"
    local temp_clean="$3"
    
    local start_time=$(grep "$start_pattern" "$temp_clean" | head -1 | sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/')
    local end_time=$(grep "$end_pattern" "$temp_clean" | head -1 | sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/')
    
    start_time=$(clean_timestamp "$start_time")
    end_time=$(clean_timestamp "$end_time")
    
    if [[ "$start_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$end_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        awk "BEGIN {printf \"%.2f\", $end_time - $start_time}"
    else
        echo "0"
    fi
}

extract_timing_metrics() {
    print_status "info" "Extracting timing metrics"
    
    local temp_clean="/tmp/qnn_clean_timing_$.txt"
    tr -d '\r' < "$QNN_OUTPUT_FILE" > "$temp_clean"
    
    # Backend creation time
    BACKEND_CREATION_TIME=$(extract_single_time_diff "QnnBackend_create started" "QnnBackend_create done successfully" "$temp_clean")
    
    # Graph composition time (from "Composing Graphs" to "Graphs Finalized")
    GRAPH_COMPOSITION_TIME=$(extract_single_time_diff "Composing Graphs" "Graphs Finalized" "$temp_clean")
    
    # Graph finalization time
    GRAPH_FINALIZATION_TIME=$(extract_single_time_diff "Finalizing Graphs" "Graphs Finalized" "$temp_clean")
    
    # Graph execution time
    GRAPH_EXECUTION_TIME=$(extract_single_time_diff "Executing Graphs" "Executed Graph" "$temp_clean")
    
    # Total inference time - from first QNN timestamp to last QNN timestamp
    local first_time=$(head -1 "$temp_clean" | sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/')
    
    # Find the last QNN-related timestamp before INFERENCE_EXIT_CODE
    # Look for the last line with a timestamp that contains QNN/INFO/WARNING before INFERENCE_EXIT_CODE
    local last_time=$(sed -n '/INFERENCE_EXIT_CODE/q;p' "$temp_clean" | \
                     grep -E "^[[:space:]]*[0-9]+\.[0-9]+ms.*\[(INFO|WARNING|ERROR)\]" | \
                     tail -1 | \
                     sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/')
    
    # If that doesn't work, try QnnBackend_free or QnnDevice_free
    if [ -z "$last_time" ] || [ "$last_time" = "" ]; then
        last_time=$(grep -E "(QnnBackend_free|QnnDevice_free)" "$temp_clean" | tail -1 | sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/')
    fi
    
    # If still nothing, use the last timestamp in the file before INFERENCE_EXIT_CODE
    if [ -z "$last_time" ] || [ "$last_time" = "" ]; then
        last_time=$(sed -n '/INFERENCE_EXIT_CODE/q;p' "$temp_clean" | \
                   grep -E "^[[:space:]]*[0-9]+\.[0-9]+ms" | \
                   tail -1 | \
                   sed -E 's/^[[:space:]]*([0-9]+\.?[0-9]*)ms.*$/\1/')
    fi
    
    first_time=$(clean_timestamp "$first_time")
    last_time=$(clean_timestamp "$last_time")
    
    if [[ "$first_time" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$last_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        TOTAL_INFERENCE_TIME=$(awk "BEGIN {printf \"%.2f\", $last_time - $first_time}")
        [ "$VERBOSE" = true ] && print_status "info" "Total inference: first=${first_time}ms, last=${last_time}ms, diff=${TOTAL_INFERENCE_TIME}ms"
    else
        TOTAL_INFERENCE_TIME=0
        print_status "warning" "Could not extract total inference time (first='$first_time', last='$last_time')"
    fi
    
    # Validate all timing values
    for var in BACKEND_CREATION_TIME GRAPH_COMPOSITION_TIME GRAPH_FINALIZATION_TIME GRAPH_EXECUTION_TIME TOTAL_INFERENCE_TIME; do
        local value=${!var}
        if ! [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            eval "$var=0"
            [ "$VERBOSE" = true ] && print_status "warning" "Invalid $var, setting to 0"
        fi
    done
    
    [ "$VERBOSE" = true ] && {
        print_status "info" "Backend creation: ${BACKEND_CREATION_TIME}ms"
        print_status "info" "Graph composition: ${GRAPH_COMPOSITION_TIME}ms"
        print_status "info" "Graph finalization: ${GRAPH_FINALIZATION_TIME}ms"
        print_status "info" "Graph execution: ${GRAPH_EXECUTION_TIME}ms"
        print_status "info" "Total inference: ${TOTAL_INFERENCE_TIME}ms"
    }
    
    rm -f "$temp_clean"
    print_status "success" "Timing metrics extracted"
}

extract_ddr_metrics() {
    print_status "info" "Extracting DDR bandwidth metrics"
    
    local temp_clean="/tmp/qnn_clean_ddr_$$.txt"
    tr -d '\r' < "$QNN_OUTPUT_FILE" > "$temp_clean"
    
    # Extract DDR bandwidth information
    if grep -q "====== DDR bandwidth summary ======" "$temp_clean"; then
        local ddr_section=$(sed -n '/====== DDR bandwidth summary ======/,/^$/p' "$temp_clean")
        
        DDR_SPILL_B=$(echo "$ddr_section" | grep "spill_bytes=" | sed 's/.*spill_bytes=//' | sed 's/[^0-9]//g')
        DDR_FILL_B=$(echo "$ddr_section" | grep "fill_bytes=" | sed 's/.*fill_bytes=//' | sed 's/[^0-9]//g')
        DDR_WRITE_TOTAL_B=$(echo "$ddr_section" | grep "write_total_bytes=" | sed 's/.*write_total_bytes=//' | sed 's/[^0-9]//g')
        DDR_READ_TOTAL_B=$(echo "$ddr_section" | grep "read_total_bytes=" | sed 's/.*read_total_bytes=//' | sed 's/[^0-9]//g')
    else
        print_status "warning" "DDR bandwidth summary not found"
        DDR_SPILL_B=0
        DDR_FILL_B=0
        DDR_WRITE_TOTAL_B=0
        DDR_READ_TOTAL_B=0
    fi
    
    # Ensure we have valid numbers
    DDR_SPILL_B=${DDR_SPILL_B:-0}
    DDR_FILL_B=${DDR_FILL_B:-0}
    DDR_WRITE_TOTAL_B=${DDR_WRITE_TOTAL_B:-0}
    DDR_READ_TOTAL_B=${DDR_READ_TOTAL_B:-0}
    
    # Validate all are numeric
    for var in DDR_SPILL_B DDR_FILL_B DDR_WRITE_TOTAL_B DDR_READ_TOTAL_B; do
        local value=${!var}
        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            eval "$var=0"
        fi
    done
    
    [ "$VERBOSE" = true ] && {
        print_status "info" "DDR spill: ${DDR_SPILL_B}B"
        print_status "info" "DDR fill: ${DDR_FILL_B}B"
        print_status "info" "DDR write total: ${DDR_WRITE_TOTAL_B}B"
        print_status "info" "DDR read total: ${DDR_READ_TOTAL_B}B"
    }
    
    rm -f "$temp_clean"
    print_status "success" "DDR metrics extracted"
}

update_metrics_csv() {
    print_status "info" "Updating metrics CSV"
    
    local temp_csv="/tmp/updated_metrics_$$.csv"
    
    # Read existing CSV
    if [ ! -f "$METRICS_CSV" ]; then
        print_status "error" "Metrics CSV not found"
        exit 1
    fi
    
    # Check if CSV has data rows
    local line_count=$(wc -l < "$METRICS_CSV")
    if [ "$line_count" -lt 2 ]; then
        print_status "error" "Metrics CSV has no data rows"
        exit 1
    fi
    
    # Update the data row with extracted metrics
    # Column mapping:
    # 10: minimum_unit_inference_time_ms
    # 11: minimum_unit_inference_file  
    # 12: maximum_unit_inference_time_ms
    # 13: maximum_unit_inference_file
    # 14: median_unit_inference_time_ms
    # 15: average_unit_inference_time_ms
    # 16: backend_creation_ms
    # 17: graph_composition_ms
    # 18: graph_finalization_ms
    # 19: graph_execution_ms
    # 20: total_inference_ms
    # 21: ddr_spill_B
    # 22: ddr_fill_B
    # 23: ddr_write_total_B
    # 24: ddr_read_total_B
    awk -F',' -v OFS=',' \
        -v min_time="$MIN_EXEC_TIME" \
        -v min_file="$MIN_EXEC_FILE" \
        -v max_time="$MAX_EXEC_TIME" \
        -v max_file="$MAX_EXEC_FILE" \
        -v median_time="$MEDIAN_EXEC_TIME" \
        -v avg_time="$AVG_EXEC_TIME" \
        -v backend_time="$BACKEND_CREATION_TIME" \
        -v compose_time="$GRAPH_COMPOSITION_TIME" \
        -v finalize_time="$GRAPH_FINALIZATION_TIME" \
        -v exec_time="$GRAPH_EXECUTION_TIME" \
        -v total_time="$TOTAL_INFERENCE_TIME" \
        -v spill_b="$DDR_SPILL_B" \
        -v fill_b="$DDR_FILL_B" \
        -v write_b="$DDR_WRITE_TOTAL_B" \
        -v read_b="$DDR_READ_TOTAL_B" \
        'NR==1 {print; next}
         NR==2 {
             $10 = min_time
             $11 = min_file
             $12 = max_time
             $13 = max_file
             $14 = median_time
             $15 = avg_time
             $16 = backend_time
             $17 = compose_time
             $18 = finalize_time
             $19 = exec_time
             $20 = total_time
             $21 = spill_b
             $22 = fill_b
             $23 = write_b
             $24 = read_b
             print
         }
         NR>2 {print}' "$METRICS_CSV" > "$temp_csv"
    
    # Replace original file
    if mv "$temp_csv" "$METRICS_CSV"; then
        print_status "success" "Metrics CSV updated successfully"
    else
        print_status "error" "Failed to update metrics CSV"
        rm -f "$temp_csv"
        exit 1
    fi
}

cleanup() {
    # Clean up temporary files
    rm -f "/tmp/execution_times_$.txt" "/tmp/updated_metrics_$.csv" "/tmp/qnn_clean_$.txt" "/tmp/qnn_clean_timing_$.txt" "/tmp/qnn_clean_ddr_$.txt" "/tmp/times_with_names_$.txt"
}

### MAIN SCRIPT : ###

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -*)
            print_status "error" "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$QNN_RUN_FOLDER" ]; then
                QNN_RUN_FOLDER="$1"
            else
                print_status "error" "Too many arguments"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Set up cleanup trap
trap cleanup EXIT

echo
echo "========================="
echo "QNN Metrics Extraction :"
echo "========================="

# Main execution
setup_environment
validate_inputs "$QNN_RUN_FOLDER"
extract_execution_times
extract_timing_metrics
extract_ddr_metrics
update_metrics_csv

echo
print_status "success" "Metrics extraction completed successfully"
print_status "info" "Updated: $METRICS_CSV"
print_status "info" "Created: $WORK_DIR/input_times.csv"

echo
echo "----- Metrics extraction completed -----"
echo

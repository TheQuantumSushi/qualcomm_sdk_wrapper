#!/bin/bash

# QNN Model Conversion Script
# Converts models to QNN format (.cpp and .bin files)

### PARAMETERS : ###

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
BLUE='\033[38;2;0;123;255m'
NC='\033[0m' # no color

# Script configuration :
SCRIPT_NAME="QNN Model Converter"
SCRIPT_VERSION="1.1.0"

# Default values :
INPUT_MODEL=""
OUTPUT_NAME=""
QUANTIZE=false
CALIBRATION_LIST=""
INPUT_DIMS=""
OUTPUT_NODES=""
BACKEND="cpu"
VERBOSE=false
FORCE=false

### HELPER FUNCTIONS : ###

print_header() {
    echo
    echo "=================================="
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "=================================="
}

print_section() {
    local title="$1"
    local length=${#title}
    local separator=$(printf '%*s' $((length + 4)) '' | tr ' ' '=')
    echo
    echo "$separator"
    echo "  $title"
    echo "$separator"
    echo
}

print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success"|"✔")
            echo -e "# ${GREEN}✔${NC} $message">&2
            ;;
        "error"|"✗")
            echo -e "# ${RED}✗${NC} $message">&2
            ;;
        "warning"|"⚠")
            echo -e "# ${YELLOW}⚠${NC} $message">&2
            ;;
        "info")
            echo "# $message">&2
            ;;
        *)
            echo "# $message">&2
            ;;
    esac
}

print_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "  [VERBOSE] $1">&2
    fi
}

show_usage() {
    cat << EOF

${BLUE}QNN Model Converter v$SCRIPT_VERSION${NC}
${BLUE}================================${NC}

${GREEN}DESCRIPTION:${NC}
    Converts models (ONNX, TensorFlow, PyTorch) to QNN format (.cpp and .bin files)
    with optional quantization for NPU/HTP acceleration using raw calibration data.

${GREEN}USAGE:${NC}
    $0 -m MODEL_PATH -o OUTPUT_NAME [OPTIONS]

${GREEN}REQUIRED ARGUMENTS:${NC}
    ${YELLOW}-m, --model MODEL_PATH${NC}     Input model path (relative to PROJECT_ROOT/models/)
    ${YELLOW}-o, --output-name OUTPUT${NC}   Output name for generated files (without extension)

${GREEN}OPTIONAL ARGUMENTS:${NC}
    ${YELLOW}-i, --input-dims DIMS${NC}      Input dimensions (e.g., "input 1,3,224,224")
    ${YELLOW}-q, --quantize${NC}             Enable quantization (requires -l)
    ${YELLOW}-l, --list LIST_FILE${NC}       Calibration list file with .raw file paths (enables quantization)
    ${YELLOW}-n, --output-nodes NODES${NC}   Output node names (comma-separated)
    ${YELLOW}-b, --backend BACKEND${NC}      Target backend: cpu, gpu, htp (affects quantization)
    ${YELLOW}-f, --force${NC}               Overwrite existing output files without confirmation
    ${YELLOW}-v, --verbose${NC}             Enable verbose conversion output
    ${YELLOW}-h, --help${NC}                Show this help message

${GREEN}SUPPORTED MODEL FORMATS:${NC}
    • ONNX (.onnx)        - Recommended format with best QNN support
    • TensorFlow (.pb)    - Protocol buffer format
    • PyTorch (.pt, .pth) - Requires manual conversion to ONNX first

${GREEN}QUANTIZATION:${NC}
    Quantization is automatically enabled when calibration list (-l) is provided.
    
    ${YELLOW}Backend-specific optimizations:${NC}
    • htp: Enhanced quantization for NPU acceleration
    • cpu/gpu: Standard quantization

    ${YELLOW}Calibration list format:${NC}
    Text file with .raw file paths (one per line):
    data/calibration/image1.raw
    data/calibration/image2.raw
    
    ${YELLOW}Raw file requirements:${NC}
    • Preprocessed tensor data in CHW format
    • Float32 data type, properly normalized
    • Same dimensions as model input

${GREEN}EXAMPLES:${NC}
    # Basic ONNX conversion (no quantization)
    $0 -m mobilenet_v2.onnx -o mobilenet_v2_converted

    # Quantized model for NPU with explicit dimensions
    $0 -m yolo11n.onnx -o yolo11n_quantized \\
       -l data/calibration_list.txt -i "images 1,3,640,640" -b htp

    # Explicit quantization with specific output nodes
    $0 -m resnet50.onnx -o resnet50_quantized \\
       -q -l data/calibration_list.txt -i "input 1,3,224,224" \\
       -n "output1,output2" -b htp

    # Force overwrite with verbose output
    $0 -m model.onnx -o model_converted -f -v

${GREEN}OUTPUT FILES:${NC}
    Generated in PROJECT_ROOT/models/:
    • OUTPUT_NAME.cpp     - QNN C++ model implementation
    • OUTPUT_NAME.bin     - QNN binary model data

${GREEN}REQUIREMENTS:${NC}
    Environment (configured by environment_setup.sh):
    • Virtual environment activated with required packages
    • QNN SDK with Python bindings
    • QUALCOMM_ROOT, QNN_ROOT, PROJECT_ROOT set

    Python packages:
    • onnx, tensorflow, torch (model format specific)
    • QNN Python converter modules

${GREEN}NEXT STEPS:${NC}
    After conversion, compile the output files:
    ./compile.sh -c OUTPUT_NAME.cpp -b OUTPUT_NAME.bin -o libOUTPUT_NAME.so

EOF
}

### ARGUMENT PARSING : ###

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--model)
                INPUT_MODEL="$2"
                shift 2
                ;;
            -o|--output-name)
                OUTPUT_NAME="$2"
                shift 2
                ;;
            -q|--quantize)
                QUANTIZE=true
                shift
                ;;
            -l|--list)
                CALIBRATION_LIST="$2"
                shift 2
                ;;
            -i|--input-dims)
                INPUT_DIMS="$2"
                shift 2
                ;;
            -n|--output-nodes)
                OUTPUT_NODES="$2"
                shift 2
                ;;
            -b|--backend)
                BACKEND="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
}

### ENVIRONMENT SETUP : ###

ensure_venv_python() {
    # Create a wrapper function that ensures python3 uses the virtual environment :
    if [ -n "$VIRTUAL_ENV" ]; then
        export PYTHON_CMD="$VIRTUAL_ENV/bin/python3"
        export PIP_CMD="$VIRTUAL_ENV/bin/pip3"
        
        # Verify the Python interpreter :
        local python_path=$($PYTHON_CMD -c "import sys; print(sys.executable)" 2>/dev/null)
        if [[ "$python_path" == "$VIRTUAL_ENV"* ]]; then
            print_verbose "Using virtual environment Python: $python_path"
        else
            print_status "warning" "Python may not be using virtual environment"
        fi
    else
        export PYTHON_CMD="python3"
        export PIP_CMD="pip3"
    fi
}

setup_environment() {
    print_section "Environment Setup"
    
    # Set QUALCOMM_ROOT if not already set :
    if [ -z "$QUALCOMM_ROOT" ]; then
        export QUALCOMM_ROOT=".."
        print_status "info" "Setting QUALCOMM_ROOT to: $(realpath $QUALCOMM_ROOT)"
    else
        print_status "success" "QUALCOMM_ROOT already set: $QUALCOMM_ROOT"
    fi
    
    # Read configuration from config.json :
    local config_file="$QUALCOMM_ROOT/scripts/config.json"
    if [ ! -f "$config_file" ]; then
        print_status "error" "config.json not found at: $config_file"
        exit 1
    fi
    
    # Check if jq is available :
    if ! command -v jq &> /dev/null; then
        print_status "error" "jq is required but not installed"
        echo "# Install with: sudo apt install jq"
        exit 1
    fi
    
    # Activate virtual environment :
    if [ -z "$VIRTUAL_ENV" ]; then
        local venv_name=$(jq -r '.names.venv' "$config_file")
        local venv_path="$QUALCOMM_ROOT/environment/virtual_environments/$venv_name"
        
        print_status "info" "Looking for virtual environment at: $venv_path"
        
        if [ -f "$venv_path/bin/activate" ]; then
            print_status "info" "Activating virtual environment: $venv_name"
            source "$venv_path/bin/activate"
            print_status "success" "Virtual environment activated: $venv_name"
        else
            print_status "error" "Virtual environment not found at: $venv_path"
            exit 1
        fi
    else
        print_status "success" "Virtual environment already active: $(basename $VIRTUAL_ENV)"
    fi
    
    # Save the virtual environment's Python paths before sourcing QNN SDK :
    local VENV_SITE_PACKAGES=""
    for site_pkg in $VIRTUAL_ENV/lib/python*/site-packages; do
        if [ -d "$site_pkg" ]; then
            VENV_SITE_PACKAGES="$site_pkg"
            break
        fi
    done
    
    print_status "info" "Virtual environment site-packages: $VENV_SITE_PACKAGES"
    
    # Export environment variables from config.json :
    export SNPE_ROOT=$(jq -r '.environment_variables.SNPE_ROOT' "$config_file" | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
    export QNN_ROOT=$(jq -r '.environment_variables.QNN_ROOT' "$config_file" | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
    export ESDK_ROOT=$(jq -r '.environment_variables.ESDK_ROOT' "$config_file" | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
    
    # Get project name and create PROJECT_ROOT :
    local project_name=$(jq -r '.names.project' "$config_file")
    export PROJECT_ROOT="$QUALCOMM_ROOT/projects/$project_name"
    
    print_status "success" "Environment variables exported"
    
    # Source QNN SDK environment :
    if [ -z "$QNN_SDK_ROOT" ]; then
        if [ -f "$QNN_ROOT/bin/envsetup.sh" ]; then
            print_status "info" "Setting up QNN SDK environment"
            
            source "$QNN_ROOT/bin/envsetup.sh"
            print_status "success" "QNN environment sourced successfully"
        else
            print_status "error" "QNN envsetup.sh not found at: $QNN_ROOT/bin/envsetup.sh"
            exit 1
        fi
    else
        print_status "success" "QNN environment already configured"
    fi
    
    # Prepend virtual environment site-packages to PYTHONPATH :
    if [ -n "$VENV_SITE_PACKAGES" ] && [ -d "$VENV_SITE_PACKAGES" ]; then
        export PYTHONPATH="$VENV_SITE_PACKAGES:$PYTHONPATH"
        print_status "success" "Virtual environment added to PYTHONPATH"
    else
        print_status "warning" "Could not find virtual environment site-packages"
    fi
    
    # Verify that virtual environment packages are accessible :
    print_status "info" "Verifying virtual environment package access"
    
    if python3 -c "import onnx; print('ONNX version:', onnx.__version__)" 2>/dev/null; then
        print_status "success" "Virtual environment packages accessible"
    else
        print_status "error" "Virtual environment packages not accessible"
        echo "# Current PYTHONPATH: $PYTHONPATH"
        echo "# Virtual environment: $VIRTUAL_ENV"
        exit 1
    fi
    
    # Setup Python command :
    ensure_venv_python
}

### VALIDATION FUNCTIONS : ###

validate_environment() {
    print_section "Environment Validation"
    
    local missing_vars=()
    
    # Check required environment variables :
    if [ -z "$QUALCOMM_ROOT" ]; then missing_vars+=("QUALCOMM_ROOT"); fi
    if [ -z "$QNN_ROOT" ]; then missing_vars+=("QNN_ROOT"); fi
    if [ -z "$ESDK_ROOT" ]; then missing_vars+=("ESDK_ROOT"); fi
    if [ -z "$PROJECT_ROOT" ]; then missing_vars+=("PROJECT_ROOT"); fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_status "error" "Missing environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "    - $var"
        done
        exit 1
    fi
    
    # Check QNN SDK :
    if [ ! -d "$QNN_ROOT" ]; then
        print_status "error" "QNN SDK not found at: $QNN_ROOT"
        exit 1
    fi
    
    # Source QNN environment setup :
    print_status "info" "Setting up QNN SDK environment"
    
    if [ -f "$QNN_ROOT/bin/envsetup.sh" ]; then
        source "$QNN_ROOT/bin/envsetup.sh"
        print_status "success" "QNN environment sourced successfully"
    else
        print_status "error" "QNN envsetup.sh not found at: $QNN_ROOT/bin/envsetup.sh"
        exit 1
    fi
    
    # Check QNN tools :
    local qnn_converter=""
    case "$(get_model_format "$PROJECT_ROOT/models/$INPUT_MODEL")" in
        "onnx")
            qnn_converter="$QNN_ROOT/bin/x86_64-linux-clang/qnn-onnx-converter"
            ;;
        "tensorflow")
            qnn_converter="$QNN_ROOT/bin/x86_64-linux-clang/qnn-tensorflow-converter"
            ;;
        "pytorch")
            qnn_converter="$QNN_ROOT/bin/x86_64-linux-clang/qnn-pytorch-converter"
            ;;
    esac
    
    if [ ! -f "$qnn_converter" ]; then
        print_status "error" "QNN converter not found: $qnn_converter"
        exit 1
    fi
    
    # Test QNN Python modules :
    print_status "info" "Testing QNN Python modules"
    
    if python3 -c "import qti.aisw.converters" 2>/dev/null; then
        print_status "success" "QNN Python modules accessible"
    else
        print_status "error" "QNN Python modules not accessible. Check PYTHONPATH"
        echo "# Current PYTHONPATH: $PYTHONPATH"
        echo "# Try running: source $QNN_ROOT/bin/envsetup.sh"
        exit 1
    fi
    
    print_status "success" "Environment validation passed"
}

validate_arguments() {
    print_section "Argument Validation"
    
    # Check required arguments :
    if [ -z "$INPUT_MODEL" ]; then
        print_status "error" "Model path is required (-m/--model)"
        show_usage
        exit 1
    fi
    
    if [ -z "$OUTPUT_NAME" ]; then
        print_status "error" "Output name is required (-o/--output-name)"
        show_usage
        exit 1
    fi
    
    # Validate model file exists :
    local full_model_path="$PROJECT_ROOT/models/$INPUT_MODEL"
    if [ ! -f "$full_model_path" ]; then
        print_status "error" "Model file not found: $full_model_path"
        exit 1
    fi
    
    # Validate backend :
    case "$BACKEND" in
        "cpu"|"gpu"|"htp")
            ;;
        *)
            print_status "error" "Invalid backend: $BACKEND"
            exit 1
            ;;
    esac
    
    # Handle quantization logic :
    if [ "$QUANTIZE" = true ] && [ -z "$CALIBRATION_LIST" ]; then
        print_status "warning" "Quantization requested but no calibration list provided (-l). Disabling quantization."
        QUANTIZE=false
    elif [ "$QUANTIZE" = false ] && [ -n "$CALIBRATION_LIST" ]; then
        print_status "info" "Calibration list provided. Enabling quantization automatically."
        QUANTIZE=true
    fi
    
    # Validate calibration list if quantization is enabled :
    if [ "$QUANTIZE" = true ]; then
        # Construct full path to calibration list relative to PROJECT_ROOT :
        local full_calib_path="$PROJECT_ROOT/$CALIBRATION_LIST"
        
        if [ ! -f "$full_calib_path" ]; then
            print_status "error" "Calibration list file not found: $full_calib_path"
            exit 1
        fi
        
        # Check if the file is a .txt file :
        if [[ "$CALIBRATION_LIST" != *.txt ]]; then
            print_status "warning" "Calibration list should be a .txt file, but proceeding anyway"
        fi
        
        # Check if calibration list already contains absolute paths
        local first_line=$(head -n 1 "$full_calib_path" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$')
        local needs_conversion=true
        
        if [[ "$first_line" = /* ]] || [[ "$first_line" = ../* ]]; then
            print_status "info" "Detected absolute or project-relative paths in calibration list"
            needs_conversion=false
            # Update CALIBRATION_LIST to use full path
            CALIBRATION_LIST="$full_calib_path"
        else
            print_status "info" "Detected relative paths in calibration list - will convert to absolute"
        fi
        
        # Validate that the file contains valid .raw file paths :
        local invalid_files=0
        local total_files=0
        local raw_files=0
        
        # Create a temporary file with absolute paths for QNN converter (only if needed)
        local temp_calib_list=""
        if [ "$needs_conversion" = "true" ]; then
            temp_calib_list=$(mktemp)
        fi
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments :
            if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            # Trim whitespace :
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            total_files=$((total_files + 1))
            
            # Convert paths to absolute :
            local file_path
            if [[ "$line" = /* ]]; then
                # Already absolute path
                file_path="$line"
            elif [[ "$line" = ../* ]]; then
                # Project-relative path (like ../projects/sncf_rail_defect/...)
                # Convert to absolute by resolving from scripts directory
                file_path="$(cd "$(dirname "$0")" && realpath "$line")"
            else
                # Relative to PROJECT_ROOT
                file_path="$PROJECT_ROOT/$line"
            fi
            
            # Check if file exists :
            if [ ! -f "$file_path" ]; then
                if [ "$VERBOSE" = true ]; then
                    print_verbose "Warning : File not found: $file_path"
                fi
                invalid_files=$((invalid_files + 1))
            else
                # Check if it's a .raw file :
                if [[ "$line" == *.raw ]]; then
                    raw_files=$((raw_files + 1))
                    print_verbose "Valid .raw file: $(basename "$line")"
                    # Write absolute path to temporary calibration list if conversion needed
                    if [ "$needs_conversion" = "true" ]; then
                        echo "$file_path" >> "$temp_calib_list"
                    fi
                else
                    print_verbose "Warning : Not a .raw file: $(basename "$line")"
                fi
            fi
        done < "$full_calib_path"
        
        if [ $total_files -eq 0 ]; then
            print_status "error" "Calibration list file is empty or contains no valid entries"
            [ -n "$temp_calib_list" ] && rm -f "$temp_calib_list"
            exit 1
        fi
        
        if [ $invalid_files -gt 0 ]; then
            print_status "warning" "$invalid_files out of $total_files files in calibration list do not exist"
            if [ $invalid_files -eq $total_files ]; then
                print_status "error" "All files in calibration list are invalid"
                [ -n "$temp_calib_list" ] && rm -f "$temp_calib_list"
                exit 1
            fi
        fi
        
        if [ $raw_files -eq 0 ]; then
            print_status "error" "No .raw files found in calibration list"
            print_status "info" "Expected format: paths to .raw files (one per line)"
            [ -n "$temp_calib_list" ] && rm -f "$temp_calib_list"
            exit 1
        fi
        
        # Update CALIBRATION_LIST to use the temporary file with absolute paths if conversion was needed
        if [ "$needs_conversion" = "true" ]; then
            CALIBRATION_LIST="$temp_calib_list"
            print_status "info" "Created temporary calibration list with absolute paths"
        fi
        
        local valid_files=$((total_files - invalid_files))
        print_status "success" "Calibration list validated: $valid_files files found ($raw_files .raw files)"
    fi
    
    print_status "success" "Argument validation passed"
}

### MODEL FORMAT DETECTION : ###

get_model_format() {
    local model_path="$1"
    local extension="${model_path##*.}"
    
    case "$extension" in
        "onnx")
            echo "onnx"
            ;;
        "pb")
            echo "tensorflow"
            ;;
        "pt"|"pth")
            echo "pytorch"
            ;;
        *)
            # Try to detect based on file content :
            if file "$model_path" | grep -q "protocol buffer"; then
                echo "tensorflow"
            else
                echo "unknown"
            fi
            ;;
    esac
}

### CONVERSION FUNCTIONS : ###

auto_detect_input_dims() {
    local model_path="$1"
    local format="$2"
    
    print_verbose "Attempting to auto-detect input dimensions"
    
    case "$format" in
        "onnx")
            # Use Python to inspect ONNX model :
            "$PYTHON_CMD" -c "
import onnx
try:
    model = onnx.load('$model_path')
    input_info = model.graph.input[0]
    input_name = input_info.name
    
    # Extract dimensions
    dims = []
    for dim in input_info.type.tensor_type.shape.dim:
        if dim.dim_value > 0:
            dims.append(str(dim.dim_value))
        else:
            dims.append('1')  # Default for dynamic dimensions
    
    print(f'{input_name} {','.join(dims)}')
except Exception as e:
    print('input 1,3,224,224')  # Default fallback
" 2>/dev/null
            ;;
        *)
            echo "input 1,3,224,224" # default fallback
            ;;
    esac
}

convert_model_to_qnn() {
    local model_path="$PROJECT_ROOT/models/$INPUT_MODEL"
    local model_format="$(get_model_format "$model_path")"
    local output_cpp="$PROJECT_ROOT/models/${OUTPUT_NAME}.cpp"
    local output_bin="$PROJECT_ROOT/models/${OUTPUT_NAME}.bin"
    
    print_section "Model Conversion to QNN"
    
    print_status "info" "Model format detected: $model_format"
    print_status "info" "Converting: $INPUT_MODEL"
    print_status "info" "Output files: ${OUTPUT_NAME}.cpp, ${OUTPUT_NAME}.bin"
    
    if [ "$QUANTIZE" = true ]; then
        print_status "info" "Quantization: ENABLED (using calibration list: $(basename "$CALIBRATION_LIST"))"
        print_status "info" "Input format: Raw tensor files (.raw)"
    else
        print_status "info" "Quantization: DISABLED"
    fi
    
    # Auto-detect input dimensions if not provided :
    if [ -z "$INPUT_DIMS" ]; then
        INPUT_DIMS="$(auto_detect_input_dims "$model_path" "$model_format")"
        print_status "info" "Auto-detected input dimensions: $INPUT_DIMS"
    fi
    
    # Check if output files already exist :
    if [ -f "$output_cpp" ] || [ -f "$output_bin" ]; then
        if [ "$FORCE" = false ]; then
            print_status "warning" "Output files already exist. Use -f/--force to overwrite"
            read -p "Continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "info" "Operation cancelled"
                exit 0
            fi
        fi
    fi
    
    # Build conversion command :
    local converter_cmd=""
    case "$model_format" in
        "onnx")
            converter_cmd="$QNN_ROOT/bin/x86_64-linux-clang/qnn-onnx-converter"
            ;;
        "tensorflow")
            converter_cmd="$QNN_ROOT/bin/x86_64-linux-clang/qnn-tensorflow-converter"
            ;;
        "pytorch")
            converter_cmd="$QNN_ROOT/bin/x86_64-linux-clang/qnn-pytorch-converter"
            ;;
        *)
            print_status "error" "Unsupported model format: $model_format"
            return 1
            ;;
    esac
    
    # Build command arguments :
    local cmd_args=(
        "--input_network" "$model_path"
        "--output_path" "$output_cpp"
    )
    
    # Add input dimensions if provided :
    if [ -n "$INPUT_DIMS" ]; then
        cmd_args+=("--input_dim" $INPUT_DIMS)
    fi
    
    # Add output nodes if specified :
    if [ -n "$OUTPUT_NODES" ]; then
        IFS=',' read -ra nodes <<< "$OUTPUT_NODES"
        for node in "${nodes[@]}"; do
            cmd_args+=("--out_node" "$node")
        done
    fi
    
    # Add quantization options for raw input files :
    if [ "$QUANTIZE" = true ]; then
        print_status "info" "Using raw tensor files for quantization"
        
        # Verify calibration list file exists :
        if [ ! -f "$CALIBRATION_LIST" ]; then
            print_status "error" "Calibration list file not found: $CALIBRATION_LIST"
            return 1
        fi
        
        cmd_args+=("--input_list" "$CALIBRATION_LIST")
        
        # Add backend-specific quantization options :
        case "$BACKEND" in
            "htp")
                cmd_args+=("--param_quantizer" "enhanced")
                cmd_args+=("--act_quantizer" "enhanced")
                ;;
        esac
    fi
    
    echo
    echo "Executing conversion command:"
    echo "$PYTHON_CMD $converter_cmd ${cmd_args[*]}"
    echo
    
    # Set PYTHONPATH explicitly for this command :
    env PYTHONPATH="$PYTHONPATH" "$PYTHON_CMD" "$converter_cmd" "${cmd_args[@]}"
    local conversion_result=$?
    
    echo
    
    if [ $conversion_result -eq 0 ] && [ -f "$output_cpp" ] && [ -f "$output_bin" ]; then
        print_status "success" "Model converted to QNN format"
        print_status "success" "CPP file: $output_cpp"
        print_status "success" "BIN file: $output_bin"
        
        # Clean up temporary calibration list if it was created
        if [[ "$CALIBRATION_LIST" == /tmp/* ]]; then
            rm -f "$CALIBRATION_LIST"
        fi
        
        return 0
    else
        print_status "error" "Model conversion failed"
        
        # Clean up temporary calibration list if it was created
        if [[ "$CALIBRATION_LIST" == /tmp/* ]]; then
            rm -f "$CALIBRATION_LIST"
        fi
        
        return 1
    fi
}

### MAIN EXECUTION : ###

main() {
    print_header
    
    # Parse command line arguments :
    parse_arguments "$@"
    
    # Setup environment first (including venv activation) :
    setup_environment
    
    # Validate environment and arguments :
    validate_environment
    validate_arguments
    
    # Ensure models directory exists :
    if [ ! -d "$PROJECT_ROOT/models" ]; then
        print_status "info" "Creating models directory: $PROJECT_ROOT/models"
        mkdir -p "$PROJECT_ROOT/models"
    fi
    
    # Convert model to QNN format :
    print_status "info" "Starting model conversion"
    
    convert_model_to_qnn
    local convert_status=$?
    
    if [ $convert_status -ne 0 ]; then
        print_status "error" "Conversion failed"
        exit 1
    fi
    
    # Summary :
    print_section "Conversion Summary"
    
    print_status "success" "Conversion completed successfully!"
    
    echo
    echo "Generated files:"
    echo "  - QNN C++ model: $PROJECT_ROOT/models/${OUTPUT_NAME}.cpp"
    echo "  - QNN binary data: $PROJECT_ROOT/models/${OUTPUT_NAME}.bin"
    
    echo
    echo "To compile these files to a shared library, use:"
    echo "  ./compile.sh -c ${OUTPUT_NAME}.cpp -b ${OUTPUT_NAME}.bin -o lib${OUTPUT_NAME}.so [OPTIONS]"
    
    # Show file sizes for verification :
    echo
    print_status "info" "File information:"
    echo "  - CPP size: $(stat -c%s "$PROJECT_ROOT/models/${OUTPUT_NAME}.cpp" 2>/dev/null || echo "unknown") bytes"
    echo "  - BIN size: $(stat -c%s "$PROJECT_ROOT/models/${OUTPUT_NAME}.bin" 2>/dev/null || echo "unknown") bytes"
    echo
}

# Execute main function with all arguments :
main "$@"

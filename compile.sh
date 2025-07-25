#!/bin/bash

# QNN Model Compilation Script
# Compiles QNN format files (.cpp and .bin) to shared library (.so)

### PARAMETERS : ###

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
BLUE='\033[38;2;0;123;255m'
NC='\033[0m' # no color

# Script configuration :
SCRIPT_NAME="QNN Model Compiler"
SCRIPT_VERSION="1.0.0"

# Default values :
CPP_FILE=""
BIN_FILE=""
OUTPUT_SO=""
TARGET_PLATFORM="aarch64-oe-linux-gcc11.2"
BACKEND="cpu"
VERBOSE=false
FORCE=false
GENERATE_CONTEXT=false

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
            echo -e "# ${GREEN}✔${NC} $message"
            ;;
        "error"|"✗")
            echo -e "# ${RED}✗${NC} $message"
            ;;
        "warning"|"⚠")
            echo -e "# ${YELLOW}⚠${NC} $message"
            ;;
        "info")
            echo "# $message"
            ;;
        *)
            echo "# $message"
            ;;
    esac
}

print_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "  [VERBOSE] $1"
    fi
}

show_usage() {
    cat << EOF

${BLUE}QNN Model Compiler v$SCRIPT_VERSION${NC}
${BLUE}==============================${NC}

${GREEN}DESCRIPTION:${NC}
    Compiles QNN format files (.cpp and .bin) generated by convert.sh into 
    shared library (.so) files ready for deployment on target devices.

${GREEN}USAGE:${NC}
    $0 -c CPP_FILE -b BIN_FILE -o OUTPUT_SO [OPTIONS]

${GREEN}REQUIRED ARGUMENTS:${NC}
    ${YELLOW}-c, --cpp CPP_FILE${NC}         QNN C++ file path (relative to PROJECT_ROOT/models/)
    ${YELLOW}-b, --bin BIN_FILE${NC}         QNN binary file path (relative to PROJECT_ROOT/models/)
    ${YELLOW}-o, --output OUTPUT_SO${NC}     Output shared library filename (relative to PROJECT_ROOT/models/)

${GREEN}OPTIONAL ARGUMENTS:${NC}
    ${YELLOW}-t, --target TARGET${NC}        Target platform (default: aarch64-oe-linux-gcc11.2)
    ${YELLOW}--backend BACKEND${NC}          Target backend: cpu, gpu, htp (affects compilation)
    ${YELLOW}--generate-context${NC}         Generate context binary for HTP backend
    ${YELLOW}-f, --force${NC}               Overwrite existing output files without confirmation
    ${YELLOW}-v, --verbose${NC}             Enable verbose compilation output
    ${YELLOW}-h, --help${NC}                Show this help message

${GREEN}TARGET PLATFORMS:${NC}
    ${YELLOW}x86_64-linux-clang${NC}         Linux x86_64 (development/testing)
    ${YELLOW}aarch64-oe-linux-gcc11.2${NC}   Qualcomm Linux devices (Rubik Pi)
    ${YELLOW}aarch64-android${NC}            Android ARM64 devices

${GREEN}EXAMPLES:${NC}
    # Basic compilation for ARM64 Linux
    $0 -c mobilenet_v2.cpp -b mobilenet_v2.bin -o libmobilenet_v2.so

    # HTP backend with context binary generation
    $0 -c resnet50_quantized.cpp -b resnet50_quantized.bin -o libresnet50.so \\
       --backend htp --generate-context

    # x86_64 compilation for local testing
    $0 -c model.cpp -b model.bin -o libmodel.so -t x86_64-linux-clang

    # Force overwrite existing files
    $0 -c model.cpp -b model.bin -o libmodel.so -f

${GREEN}INPUT FILES:${NC}
    Required files generated by convert.sh:
    • CPP_FILE    - QNN model C++ implementation
    • BIN_FILE    - QNN model binary data

${GREEN}OUTPUT FILES:${NC}
    • OUTPUT_SO           - Shared library ready for deployment
    • *_context.bin       - Context binary (if --generate-context used)

${GREEN}REQUIREMENTS:${NC}
    Environment variables (set by environment_setup.sh):
    • QUALCOMM_ROOT       - Root directory path
    • QNN_ROOT           - QNN SDK installation path
    • ESDK_ROOT          - Embedded SDK path
    • PROJECT_ROOT       - Current project path
    • QNN_AARCH64_LINUX_OE_GCC_112 - Cross-compiler path (for ARM64)

    Tools required:
    • QNN SDK with qnn-model-lib-generator
    • Cross-compilation toolchain (for non-x86_64 targets)

${GREEN}NEXT STEPS:${NC}
    After compilation, use the generated .so file with:
    • qnn_inference.sh for single model testing
    • batch_inference.sh for multiple model comparison

EOF
}

### ARGUMENT PARSING : ###

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cpp)
                CPP_FILE="$2"
                shift 2
                ;;
            -b|--bin)
                BIN_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_SO="$2"
                shift 2
                ;;
            -t|--target)
                TARGET_PLATFORM="$2"
                shift 2
                ;;
            --backend)
                BACKEND="$2"
                shift 2
                ;;
            --generate-context)
                GENERATE_CONTEXT=true
                shift
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
                
                ;;
        esac
    done
}

### ENVIRONMENT SETUP : ###

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
        
    fi
    
    # Check if jq is available :
    if ! command -v jq &> /dev/null; then
        print_status "error" "jq is required but not installed"
        echo "# Install with: sudo apt install jq"
        
    fi
    
    # Export environment variables from config.json :
    export SNPE_ROOT=$(jq -r '.environment_variables.SNPE_ROOT' "$config_file" | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
    export QNN_ROOT=$(jq -r '.environment_variables.QNN_ROOT' "$config_file" | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
    export ESDK_ROOT=$(jq -r '.environment_variables.ESDK_ROOT' "$config_file" | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
    
    # Get project name and create PROJECT_ROOT :
    local project_name=$(jq -r '.names.project' "$config_file")
    export PROJECT_ROOT="$QUALCOMM_ROOT/projects/$project_name"
    
    # Export cross-compiler path :
    export QNN_AARCH64_LINUX_OE_GCC_112="$ESDK_ROOT/tmp/"
    
    print_status "success" "Environment variables exported"
    
    # Source QNN SDK environment :
    if [ -z "$QNN_SDK_ROOT" ]; then
        if [ -f "$QNN_ROOT/bin/envsetup.sh" ]; then
            print_status "info" "Setting up QNN SDK environment"
            
            source "$QNN_ROOT/bin/envsetup.sh"
            print_status "success" "QNN environment sourced successfully"
        else
            print_status "error" "QNN envsetup.sh not found at: $QNN_ROOT/bin/envsetup.sh"
            
        fi
    else
        print_status "success" "QNN environment already configured"
    fi
    
    # Source toolchain environment if available :
    local toolchain_setup="$ESDK_ROOT/environment-setup-armv8-2a-qcom-linux"
    if [ -f "$toolchain_setup" ]; then
        source "$toolchain_setup" &>/dev/null
        print_status "success" "Toolchain environment sourced"
    fi
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
    
    if [ "$TARGET_PLATFORM" = "aarch64-oe-linux-gcc11.2" ] && [ -z "$QNN_AARCH64_LINUX_OE_GCC_112" ]; then
        missing_vars+=("QNN_AARCH64_LINUX_OE_GCC_112")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_status "error" "Missing environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "    - $var"
        done
        
    fi
    
    # Check QNN SDK :
    if [ ! -d "$QNN_ROOT" ]; then
        print_status "error" "QNN SDK not found at: $QNN_ROOT"
        
    fi
    
    # Check model lib generator :
    if [ ! -f "$QNN_ROOT/bin/x86_64-linux-clang/qnn-model-lib-generator" ]; then
        print_status "error" "QNN model lib generator not found"
        
    fi
    
    # Check context binary generator if needed :
    if [ "$GENERATE_CONTEXT" = true ]; then
        if [ ! -f "$QNN_ROOT/bin/x86_64-linux-clang/qnn-context-binary-generator" ]; then
            print_status "error" "QNN context binary generator not found"
            
        fi
    fi
    
    print_status "success" "Environment validation passed"
}

validate_arguments() {
    print_section "Argument Validation"
    
    # Check required arguments :
    if [ -z "$CPP_FILE" ]; then
        print_status "error" "CPP file is required (-c/--cpp)"
        show_usage
        
    fi
    
    if [ -z "$BIN_FILE" ]; then
        print_status "error" "BIN file is required (-b/--bin)"
        show_usage
        
    fi
    
    if [ -z "$OUTPUT_SO" ]; then
        print_status "error" "Output SO file is required (-o/--output)"
        show_usage
        
    fi
    
    # Validate input files exist :
    local full_cpp_path="$PROJECT_ROOT/models/$CPP_FILE"
    local full_bin_path="$PROJECT_ROOT/models/$BIN_FILE"
    
    if [ ! -f "$full_cpp_path" ]; then
        print_status "error" "CPP file not found: $full_cpp_path"
        
    fi
    
    if [ ! -f "$full_bin_path" ]; then
        print_status "error" "BIN file not found: $full_bin_path"
        
    fi
    
    # Validate target platform :
    case "$TARGET_PLATFORM" in
        "x86_64-linux-clang"|"aarch64-oe-linux-gcc11.2"|"aarch64-android")
            ;;
        *)
            print_status "error" "Invalid target platform: $TARGET_PLATFORM"
            
            ;;
    esac
    
    # Validate backend :
    case "$BACKEND" in
        "cpu"|"gpu"|"htp")
            ;;
        *)
            print_status "error" "Invalid backend: $BACKEND"
            
            ;;
    esac
    
    print_status "success" "Argument validation passed"
}

### COMPILATION FUNCTIONS : ###

compile_qnn_model() {
    local cpp_path="$PROJECT_ROOT/models/$CPP_FILE"
    local bin_path="$PROJECT_ROOT/models/$BIN_FILE"
    local output_path="$PROJECT_ROOT/models/$OUTPUT_SO"
    
    print_section "QNN Model Compilation" >&2
    
    print_verbose "CPP file: $cpp_path" >&2
    print_verbose "BIN file: $bin_path" >&2
    print_verbose "Output SO: $output_path" >&2
    
    # Check if output file already exists :
    if [ -f "$output_path" ]; then
        if [ "$FORCE" = false ]; then
            echo
            print_status "warning" "Output file already exists. Use -f/--force to overwrite" >&2
            read -p "Continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "info" "Operation cancelled" >&2
                exit 0
            fi
        fi
    fi
    
    # Create temporary compilation directory :
    local temp_lib_output="$PROJECT_ROOT/models/temp_libs"
    mkdir -p "$temp_lib_output"
    
    # Build compilation command :
    local compile_cmd="$QNN_ROOT/bin/x86_64-linux-clang/qnn-model-lib-generator"
    local cmd_args=(
        "-c" "$cpp_path"
        "-b" "$bin_path"
        "-o" "$temp_lib_output"
        "-t" "$TARGET_PLATFORM"
    )
    
    # Add backend-specific options :
    # Note : Backend-specific optimizations are handled during conversion phase
    # The model-lib-generator doesn't have backend-specific flags
    
    print_status "info" "Compiling for target: $TARGET_PLATFORM" >&2
    print_status "info" "CPP file: $cpp_path" >&2
    print_status "info" "BIN file: $bin_path" >&2
    print_status "info" "Output SO: $output_path" >&2
    
    echo >&2
    echo "Executing compilation command:" >&2
    echo "$compile_cmd ${cmd_args[*]}" >&2
    echo >&2
    
    # Execute compilation :
    "$compile_cmd" "${cmd_args[@]}"
    local compilation_result=$?
    
    echo >&2
    
    # Check results and move to final location :
    local model_basename="$(basename "$CPP_FILE" .cpp)"
    local temp_lib_file="$temp_lib_output/$TARGET_PLATFORM/lib${model_basename}.so"
    
    if [ $compilation_result -eq 0 ] && [ -f "$temp_lib_file" ]; then
        # Move the .so file to the specified output location :
        print_status "info" "Moving library to final location" >&2
        
        if mv "$temp_lib_file" "$output_path" 2>/dev/null; then
            print_status "success" "Model compiled successfully: $output_path" >&2
            
            # Clean up temporary directory :
            rm -rf "$temp_lib_output"
            
            echo "$output_path"
            return 0
        else
            print_status "error" "Failed to move library to final location" >&2
            return 1
        fi
    else
        print_status "error" "Model compilation failed" >&2
        
        # Debug information :
        print_status "info" "Expected library file: $temp_lib_file" >&2
        if [ -d "$temp_lib_output/$TARGET_PLATFORM" ]; then
            print_status "info" "Files in target directory:" >&2
            ls -la "$temp_lib_output/$TARGET_PLATFORM/" 2>/dev/null | head -10 >&2
        else
            print_status "info" "Target directory not created: $temp_lib_output/$TARGET_PLATFORM" >&2
        fi
        
        return 1
    fi
}

generate_context_binary() {
    local lib_file="$1"
    local output_dir="$(dirname "$lib_file")"
    local model_basename="$(basename "$lib_file" .so | sed 's/^lib//')"
    local context_file="$output_dir/${model_basename}_context.bin"
    
    print_section "Context Binary Generation" >&2
    
    if [ "$BACKEND" = "htp" ]; then
        print_status "info" "Generating context binary for HTP backend" >&2
        
        local context_cmd="$QNN_ROOT/bin/x86_64-linux-clang/qnn-context-binary-generator"
        local backend_lib="$QNN_ROOT/target/x86_64-linux-clang/lib/libQnnHtp.so"
        
        local cmd_args=(
            "--backend" "$backend_lib"
            "--model" "$lib_file"
            "--binary_file" "$context_file"
        )
        
        echo >&2
        echo "Executing context generation command:" >&2
        echo "$context_cmd ${cmd_args[*]}" >&2
        echo >&2
        
        "$context_cmd" "${cmd_args[@]}"
        local context_result=$?
        
        echo >&2
        
        if [ $context_result -eq 0 ] && [ -f "$context_file" ]; then
            print_status "success" "Context binary generated: $context_file" >&2
            echo "$context_file"
        else
            print_status "warning" "Context binary generation failed (optional for HTP)" >&2
        fi
    else
        print_status "info" "Context binary generation requested but not applicable for $BACKEND backend" >&2
    fi
}

### MAIN EXECUTION : ###

main() {
    print_header
    
    # Parse command line arguments :
    parse_arguments "$@"
    
    # Setup environment :
    setup_environment
    
    # Validate environment and arguments :
    validate_environment
    validate_arguments
    
    # Ensure models directory exists :
    if [ ! -d "$PROJECT_ROOT/models" ]; then
        print_status "error" "Models directory not found: $PROJECT_ROOT/models"
        
    fi
    
    # Compile QNN model to shared library :
    print_status "info" "Starting model compilation"
    
    local lib_result
    lib_result="$(compile_qnn_model)"
    local compile_status=$?
    
    if [ $compile_status -ne 0 ]; then
        print_status "error" "Compilation failed"
        
    fi
    
    # Generate context binary (if requested) :
    local context_result=""
    if [ "$GENERATE_CONTEXT" = true ]; then
        context_result="$(generate_context_binary "$lib_result")"
    else
        echo
        print_status "info" "Context binary generation not requested"
    fi
    
    # Summary :
    print_section "Compilation Summary"
    
    print_status "success" "Compilation completed successfully!"
    
    echo
    echo "Generated files:"
    echo "  - Shared library: $lib_result"
    
    if [ -n "$context_result" ]; then
        echo "  - Context binary: $context_result"
    fi
    
    echo
    echo "Model ready for deployment on target platform: $TARGET_PLATFORM"
    
    if [ "$BACKEND" = "htp" ]; then
        echo "Model is optimized for: $BACKEND backend"
    fi
    
    echo
    print_status "info" "To run inference, use: ./run_inference.sh -m $OUTPUT_SO"
    
    # Show final file sizes for verification :
    echo
    print_status "info" "File information:"
    if [ -f "$lib_result" ]; then
        echo "  - Library size: $(stat -c%s "$lib_result" 2>/dev/null || echo "unknown") bytes"
    fi
    echo
}

# Execute main function with all arguments :
main "$@"

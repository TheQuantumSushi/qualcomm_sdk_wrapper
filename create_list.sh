#!/bin/bash

# Create file lists from project directories with various selection options
# Usage : see ./create_list.sh -h

### PARAMETERS : ###

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
BLUE='\033[38;2;0;123;255m'
NC='\033[0m' # no color

# Script configuration :
SCRIPT_NAME="create_list.sh"
VERSION="1.0.0"

# Function to display help :
show_help() {
    cat << EOF

${BLUE}File List Creator v$VERSION${NC}
${BLUE}===========================${NC}

${GREEN}DESCRIPTION:${NC}
    Creates file lists from project directories with various selection and filtering 
    options. Supports random selection, duplicate handling, and generates paths 
    compatible with QNN tools.

${GREEN}USAGE:${NC}
    $SCRIPT_NAME -i INPUT_PATH -o OUTPUT_PATH [OPTIONS]

${GREEN}REQUIRED ARGUMENTS:${NC}
    ${YELLOW}-i, --input INPUT_PATH${NC}     Input directory path (relative to PROJECT_DATA_ROOT)
    ${YELLOW}-o, --output OUTPUT_PATH${NC}   Output text file path (relative to PROJECT_DATA_ROOT)

${GREEN}OPTIONAL ARGUMENTS:${NC}
    ${YELLOW}-n, --count NUMBER${NC}         Number of files to select (default: all files)
    ${YELLOW}-r, --random${NC}              Enable random file selection (requires -n)
    ${YELLOW}-d, --duplicates${NC}          Allow duplicates when count > available files (requires -n)
    ${YELLOW}-e, --extensions EXTS${NC}     Filter by file extensions (comma-separated: "jpg,png,raw")
    ${YELLOW}-R, --recursive${NC}           Search subdirectories recursively
    ${YELLOW}--absolute${NC}               Use absolute paths (default, QNN-compatible)
    ${YELLOW}--relative${NC}               Use relative paths (relative to PROJECT_DATA_ROOT)
    ${YELLOW}--sort${NC}                   Sort output paths alphabetically
    ${YELLOW}-h, --help${NC}               Show this help message

${GREEN}SELECTION MODES:${NC}
    ${YELLOW}All files (no -n):${NC}         Process all found files (ignores -r and -d)
    ${YELLOW}Sequential (default):${NC}      Select files in alphabetical order (when -n used)
    ${YELLOW}Random (-r):${NC}              Randomly shuffle before selection (requires -n)

${GREEN}DUPLICATE HANDLING:${NC}
    ${YELLOW}Without -d:${NC}               Error if requested count > available files
    ${YELLOW}With -d:${NC}                  Cycle through available files to reach target count

${GREEN}EXAMPLES:${NC}
    # Create list of all files in detection/test/raw directory
    $SCRIPT_NAME -i detection/test/raw -o lists/all_test_images.txt

    # Random selection of 100 files with duplicates allowed
    $SCRIPT_NAME -i calibration/raw -n 100 -o lists/calibration_100.txt -r -d

    # Filter JPG/PNG files, recursive search, sorted output
    $SCRIPT_NAME -i validation/images -o lists/validation_photos.txt \\
                 -e "jpg,png" -R --sort

    # First 50 files with relative paths instead of absolute
    $SCRIPT_NAME -i models -n 50 -o lists/model_subset.txt --relative

    # All RAW files from current directory and subdirectories
    $SCRIPT_NAME -i . -o lists/all_raw_files.txt -e "raw" -R

${GREEN}OUTPUT FORMATS:${NC}
    ${YELLOW}Absolute paths (default):${NC}  Full system paths (recommended for QNN tools)
        /full/path/to/project/data/detection/test/raw/image1.jpg
    
    ${YELLOW}Relative paths (--relative):${NC} Paths relative to PROJECT_DATA_ROOT
        detection/test/raw/image1.jpg

${GREEN}FILE FILTERING:${NC}
    ${YELLOW}Extensions (-e):${NC}          Only include files with specified extensions
    ${YELLOW}Recursive (-R):${NC}           Include files from subdirectories
    ${YELLOW}Sort (--sort):${NC}            Alphabetically sort the output list

${GREEN}PROJECT STRUCTURE:${NC}
    The script operates within the project structure:
    PROJECT_ROOT/
    └── data/               <- PROJECT_DATA_ROOT
        ├── INPUT_PATH/     <- Source directory
        └── OUTPUT_PATH     <- Generated list file

${GREEN}REQUIREMENTS:${NC}
    • config.json in current directory with project name
    • Project data directory must exist
    • Write permissions for output file location
    • jq for JSON parsing

${GREEN}EXIT CODES:${NC}
    0    Success
    1    Error (missing arguments, invalid paths, insufficient files, etc.)

EOF
}

# Function to validate number :
validate_number() {
    local number="$1"
    local name="$2"
    
    # Check if it's a positive integer :
    if ! [[ "$number" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}Error : $name must be a positive integer (got: '$number')${NC}" >&2
        return 1
    fi
    
    # Check reasonable limits :
    if [ "$number" -gt 1000000 ]; then
        echo -e "${RED}Error : $name is too large (maximum: 1,000,000)${NC}" >&2
        return 1
    fi
    
    return 0
}

# Function to validate path :
validate_path() {
    local path="$1"
    local name="$2"
    local must_exist="$3"
    
    # Check if path is empty :
    if [ -z "$path" ]; then
        echo -e "${RED}Error : $name cannot be empty${NC}" >&2
        return 1
    fi
    
    # Check for invalid characters :
    if [[ "$path" =~ [[:space:]]*$ ]] && [ ${#path} -eq 0 ]; then
        echo -e "${RED}Error : $name cannot be only whitespace${NC}" >&2
        return 1
    fi
    
    # Convert relative path to absolute :
    local full_path
    if [[ "$path" = /* ]]; then
        full_path="$path"
    elif [[ "$path" = ../* ]]; then
        # Handle paths that go outside data directory (like ../models)
        full_path="$PROJECT_ROOT/${path#../}"
    else
        full_path="$PROJECT_DATA_ROOT/$path"
    fi
    
    # Check if path must exist :
    if [ "$must_exist" = "true" ] && [ ! -e "$full_path" ]; then
        echo -e "${RED}Error : $name does not exist : $full_path${NC}" >&2
        return 1
    fi
    
    echo "$full_path"
    return 0
}

# Function to validate extensions :
validate_extensions() {
    local extensions="$1"
    
    # Split by comma and validate each extension :
    IFS=',' read -ra ext_array <<< "$extensions"
    for ext in "${ext_array[@]}"; do
        # Remove leading/trailing whitespace :
        ext=$(echo "$ext" | xargs)
        
        # Check if extension is valid :
        if [[ ! "$ext" =~ ^[a-zA-Z0-9]+$ ]]; then
            echo -e "${RED}Error : Invalid file extension : '$ext' (only alphanumeric characters allowed)${NC}" >&2
            return 1
        fi
    done
    
    return 0
}

# Function to get files from directory :
get_files_from_directory() {
    local input_dir="$1"
    local extensions="$2"
    local recursive="$3"
    local -n files_array=$4
    
    local find_cmd="find"
    local find_args=()
    
    # Set search depth :
    if [ "$recursive" = "true" ]; then
        find_args+=("$input_dir")
    else
        find_args+=("$input_dir" "-maxdepth" "1")
    fi
    
    # Add file type filter :
    find_args+=("-type" "f")
    
    # Add extension filters :
    if [ -n "$extensions" ]; then
        find_args+=("(" "-false")
        
        IFS=',' read -ra ext_array <<< "$extensions"
        for ext in "${ext_array[@]}"; do
            ext=$(echo "$ext" | xargs)  # Remove whitespace
            find_args+=("-o" "-iname" "*.$ext")
        done
        
        find_args+=(")")
    fi
    
    # Execute find command and populate array :
    while IFS= read -r -d '' file; do
        files_array+=("$file")
    done < <("$find_cmd" "${find_args[@]}" -print0 2>/dev/null)
    
    return 0
}

# Function to shuffle array :
shuffle_array() {
    local -n arr=$1
    local i tmp size rand
    
    size=${#arr[@]}
    for ((i=size-1; i>0; i--)); do
        rand=$((RANDOM % (i+1)))
        tmp="${arr[i]}"
        arr[i]="${arr[rand]}"
        arr[rand]="$tmp"
    done
}

# Function to sort array :
sort_array() {
    local -n arr=$1
    local sorted_array
    
    # Use printf to create newline-separated list, sort it, then read back :
    readarray -t sorted_array < <(printf '%s\n' "${arr[@]}" | sort)
    arr=("${sorted_array[@]}")
}

# Function to create file list :
create_list() {
    local input_path="$1"
    local file_count="$2"
    local output_path="$3"
    local random_selection="$4"
    local allow_duplicates="$5"
    local extensions="$6"
    local recursive="$7"
    local use_absolute="$8"
    local sort_output="$9"
    
    echo "=========================================="
    echo "Creating file list"
    echo "=========================================="
    echo "Project: $PROJECT_NAME"
    echo
    
    # Validate and resolve paths :
    echo "Validating paths..."
    
    local full_input_path
    if ! full_input_path=$(validate_path "$input_path" "Input directory" "true"); then
        return 1
    fi
    
    local full_output_path
    if ! full_output_path=$(validate_path "$output_path" "Output file" "false"); then
        return 1
    fi
    
    # Check if input is a directory :
    if [ ! -d "$full_input_path" ]; then
        echo -e "${RED}Error : Input path is not a directory : $full_input_path${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✔${NC} Input directory : $full_input_path"
    echo -e "${GREEN}✔${NC} Output file : $full_output_path"
    echo
    
    # Create output directory if needed :
    local output_dir=$(dirname "$full_output_path")
    if [ ! -d "$output_dir" ]; then
        echo "Creating output directory : $output_dir"
        if ! mkdir -p "$output_dir"; then
            echo -e "${RED}Error : Failed to create output directory : $output_dir${NC}" >&2
            return 1
        fi
        echo -e "${GREEN}✔${NC} Output directory created"
        echo
    fi
    
    # Get files from directory :
    echo "Scanning for files..."
    local files=()
    
    if ! get_files_from_directory "$full_input_path" "$extensions" "$recursive" files; then
        echo -e "${RED}Error : Failed to scan directory for files${NC}" >&2
        return 1
    fi
    
    local total_files=${#files[@]}
    echo -e "${GREEN}✔${NC} Found $total_files files"
    
    # Display filter information :
    if [ -n "$extensions" ]; then
        echo "  Filtered by extensions : $extensions"
    fi
    if [ "$recursive" = "true" ]; then
        echo "  Recursive search enabled"
    fi
    echo
    
    # Check if we have any files :
    if [ $total_files -eq 0 ]; then
        echo -e "${RED}Error : No files found in directory${NC}" >&2
        return 1
    fi
    
    # Check file count requirements :
    local process_all_files=false
    if [ -z "$file_count" ]; then
        process_all_files=true
        file_count=$total_files
        echo "Processing all $total_files files"
    else
        echo "Processing $file_count of $total_files files"
        
        if [ $file_count -gt $total_files ] && [ "$allow_duplicates" = "false" ]; then
            echo -e "${RED}Error : Not enough files found${NC}" >&2
            echo "Requested : $file_count files"
            echo "Available : $total_files files"
            echo "Use -d/--duplicates flag to allow duplicates"
            return 1
        fi
    fi
    
    # Process file selection :
    echo "Processing file selection..."
    
    local selected_files=()
    if [ "$process_all_files" = "true" ]; then
        # Use all files as-is (no selection needed) :
        echo "Using all available files..."
        selected_files=("${files[@]}")
        echo -e "${GREEN}✔${NC} All $total_files files selected"
    else
        # Random shuffle if requested :
        if [ "$random_selection" = "true" ]; then
            echo "Shuffling files randomly..."
            shuffle_array files
            echo -e "${GREEN}✔${NC} Files shuffled"
        else
            echo "Using sequential order..."
            echo -e "${GREEN}✔${NC} Files in alphabetical order"
        fi
        
        # Build selected files list :
        local i=0
        
        while [ ${#selected_files[@]} -lt $file_count ]; do
            # If we need duplicates and reached end of list, restart from beginning :
            if [ $i -ge $total_files ]; then
                if [ "$allow_duplicates" = "true" ]; then
                    i=0
                else
                    break
                fi
            fi
            
            selected_files+=("${files[i]}")
            ((i++))
        done
        
        echo -e "${GREEN}✔${NC} Selected ${#selected_files[@]} files"
        
        # Handle duplicates information :
        if [ $file_count -gt $total_files ] && [ "$allow_duplicates" = "true" ]; then
            local duplicates=$((file_count - total_files))
            echo -e "${YELLOW}⚠${NC} Using $duplicates duplicate entries"
        fi
    fi
    echo
    
    # Sort output if requested :
    if [ "$sort_output" = "true" ]; then
        echo "Sorting output paths..."
        sort_array selected_files
        echo -e "${GREEN}✔${NC} Output paths sorted alphabetically"
        echo
    fi
    
    # Generate output paths :
    echo "Generating output file..."
    local output_content=()
    
    for file in "${selected_files[@]}"; do
        if [ "$use_relative" = "true" ]; then
            # Use relative path from PROJECT_DATA_ROOT :
            local relative_path
            if [[ "$file" == "$PROJECT_DATA_ROOT"/* ]]; then
                relative_path="${file#$PROJECT_DATA_ROOT/}"
            else
                # Handle files outside data directory (like models)
                relative_path="${file#$PROJECT_ROOT/}"
            fi
            output_content+=("$relative_path")
        else
            # Always use absolute paths for compatibility with QNN tools (default) :
            output_content+=("$file")
        fi
    done
    
    # Write to output file :
    printf '%s\n' "${output_content[@]}" > "$full_output_path"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error : Failed to write output file : $full_output_path${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✔${NC} File list created successfully"
    echo
    
    # Display summary :
    echo "=========================================="
    echo -e "${GREEN}✔ File list generation completed!${NC}"
    echo "=========================================="
    echo
    echo "Summary :"
    echo "  Input directory    : $input_path"
    if [ "$process_all_files" = "true" ]; then
        echo "  Files processed    : All $total_files files"
        echo "  Selection mode     : All files (no selection applied)"
    else
        echo "  Files processed    : ${#selected_files[@]} of $total_files available"
        echo "  Selection mode     : $([ "$random_selection" = "true" ] && echo "Random" || echo "Sequential")"
        echo "  Duplicates allowed : $([ "$allow_duplicates" = "true" ] && echo "Yes" || echo "No")"
    fi
    echo "  Path format        : $([ "$use_relative" = "true" ] && echo "Relative" || echo "Absolute")"
    echo "  Output sorted      : $([ "$sort_output" = "true" ] && echo "Yes" || echo "No")"
    if [ -n "$extensions" ]; then
        echo "  File extensions    : $extensions"
    fi
    echo "  Recursive search   : $([ "$recursive" = "true" ] && echo "Yes" || echo "No")"
    echo
    echo "Output file : $output_path"
    echo "Full path   : $full_output_path"
    echo
    
    return 0
}

# Main function :
main() {
    # Check if jq is available for JSON parsing :
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required for JSON parsing${NC}"
        echo "Install it with: sudo apt install jq"
        exit 1
    fi

    # Check if config.json exists :
    if [ ! -f "config.json" ]; then
        echo -e "${RED}Error: config.json not found in current directory${NC}"
        exit 1
    fi

    # Get project information from config.json :
    PROJECT_NAME=$(jq -r '.names.project' config.json 2>/dev/null)
    if [ "$PROJECT_NAME" = "null" ] || [ -z "$PROJECT_NAME" ]; then
        echo -e "${RED}Error: Could not read project name from config.json${NC}"
        exit 1
    fi

    # Set up project paths :
    QUALCOMM_ROOT=".."
    PROJECT_ROOT="$QUALCOMM_ROOT/projects/$PROJECT_NAME"
    PROJECT_DATA_ROOT="$PROJECT_ROOT/data"

    # Verify project directories exist :
    if [ ! -d "$PROJECT_ROOT" ]; then
        echo -e "${RED}Error: Project directory not found: $PROJECT_ROOT${NC}"
        exit 1
    fi

    if [ ! -d "$PROJECT_DATA_ROOT" ]; then
        echo -e "${RED}Error: Project data directory not found: $PROJECT_DATA_ROOT${NC}"
        exit 1
    fi
    
    # Initialize variables :
    local input_path=""
    local file_count=""
    local output_path=""
    local random_selection=false
    local allow_duplicates=false
    local extensions=""
    local recursive=false
    local use_absolute=true
    local use_relative=false
    local sort_output=false
    
    # Parse arguments :
    if [ $# -eq 0 ]; then
        echo
        echo -e "${RED}Error : No arguments provided${NC}" >&2
        echo "Use : $SCRIPT_NAME -i <input_path> -o <output_path> [-n <count>]"
        echo "Use : $SCRIPT_NAME --help for more information"
        echo
        exit 1
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--input)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Input path is required after $1${NC}" >&2
                    exit 1
                fi
                input_path="$2"
                shift 2
                ;;
            -n|--count)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : File count is required after $1${NC}" >&2
                    exit 1
                fi
                file_count="$2"
                shift 2
                ;;
            -o|--output)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Output path is required after $1${NC}" >&2
                    exit 1
                fi
                output_path="$2"
                shift 2
                ;;
            -r|--random)
                random_selection=true
                shift
                ;;
            -d|--duplicates)
                allow_duplicates=true
                shift
                ;;
            -e|--extensions)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Extensions list is required after $1${NC}" >&2
                    exit 1
                fi
                extensions="$2"
                shift 2
                ;;
            -R|--recursive)
                recursive=true
                shift
                ;;
            --absolute)
                use_absolute=true
                use_relative=false
                shift
                ;;
            --relative)
                use_absolute=false
                use_relative=true
                shift
                ;;
            --sort)
                sort_output=true
                shift
                ;;
            *)
                echo -e "${RED}Error : Unknown option : $1${NC}" >&2
                echo "Use : $SCRIPT_NAME --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments :
    if [ -z "$input_path" ]; then
        echo -e "${RED}Error : Input path is required (-i/--input)${NC}" >&2
        exit 1
    fi
    
    if [ -z "$output_path" ]; then
        echo -e "${RED}Error : Output path is required (-o/--output)${NC}" >&2
        exit 1
    fi
    
    # Validate count-dependent arguments :
    if [ -z "$file_count" ]; then
        # Processing all files - random and duplicates are not applicable :
        if [ "$random_selection" = true ]; then
            echo -e "${RED}Error : Random selection (-r/--random) requires specifying file count (-n/--count)${NC}" >&2
            exit 1
        fi
        
        if [ "$allow_duplicates" = true ]; then
            echo -e "${RED}Error : Duplicate handling (-d/--duplicates) requires specifying file count (-n/--count)${NC}" >&2
            exit 1
        fi
    else
        # Validate file count when specified :
        if ! validate_number "$file_count" "File count"; then
            exit 1
        fi
    fi
    
    # Validate extensions if provided :
    if [ -n "$extensions" ] && ! validate_extensions "$extensions"; then
        exit 1
    fi
    
    # Execute file list creation :
    echo
    if ! create_list "$input_path" "$file_count" "$output_path" "$random_selection" "$allow_duplicates" "$extensions" "$recursive" "$use_absolute" "$sort_output"; then
        echo
        exit 1
    fi
    
    echo
}

# Run main function with all arguments :
main "$@"

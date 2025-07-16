#!/bin/bash

# Setup the environment :
# - export environment variables
# - assess presence of necessary packages/libraries/tools
# - source required files
# ALWAYS USE SOURCE AND NOT ./ SO THAT ENVIRONMENT VARIABLES CAN PERSIST

### PARAMETERS : ###

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
NC='\033[0m' # no color

# Character limit for display :
MAX_PACKAGE_LENGTH=25
MAX_LIBRARY_LENGTH=25

# Required packages :
packages=(
    "repo" "gawk" "wget" "git" "diffstat" "unzip" "texinfo" "gcc" 
    "build-essential" "chrpath" "socat" "cpio" "python3" "python3-pip" 
    "python3-pexpect" "xz-utils" "debianutils" "iputils-ping" "python3-git" 
    "python3-jinja2" "libegl1-mesa" "libsdl1.2-dev" "pylint" "xterm" 
    "python3-subunit" "mesa-common-dev" "zstd" "liblz4-tool" "locales" 
    "tar" "python-is-python3" "file" "libxml-opml-simplegen-perl" "vim" 
    "whiptail" "bc" "lib32stdc++6" "libncurses5" "checkinstall" 
    "libreadline-dev" "libncursesw5-dev" "libssl-dev" "libsqlite3-dev" 
    "tk-dev" "libgdbm-dev" "libc6-dev" "libbz2-dev" "libffi-dev" 
    "curl" "git-lfs" "libncurses5-dev" "libncursesw5-dev"
)

# Required Python libraries (library:version) :
REQUIRED_LIBRARIES=(
    "pefile:None" 
    "requests:2.31.0" 
    "numpy:None" 
    "qai_hub:None"
    "tensorflow:2.10.1"
    "tflite:2.3.0"
    "torch:1.13.1"
    "torchvision:0.14.1"
    "onnx:1.12.0"
    "onnxruntime:1.17.1"
    "onnxsim:0.4.36"
)

### START-UP CHECK : ###

echo
echo "============================"
echo "Starting environment check : "
echo "============================"

# Export environment root variable :
echo
export QUALCOMM_ROOT=".."
if [ -n "$QUALCOMM_ROOT" ]; then
   echo -e "# ${GREEN}✔${NC} Environment root QUALCOMM_ROOT set to : $(realpath $QUALCOMM_ROOT)"
else
   echo -e "# ${RED}⚠ QUALCOMM_ROOT could not be set"
   
fi

# Check if jq is installed for JSON parsing :
if ! command -v jq &> /dev/null; then
    echo -e "# ${RED}⚠ Package jq is missing${NC}"
    echo "# It is required for JSON parsing, install it with :"
    echo "sudo apt install jq"
    
else
    echo -e "# ${GREEN}✔${NC} Package jq is present"
fi

# Fetch venv name from config.json early for folder structure check :
if [ -f "config.json" ]; then
    VENV_NAME=$(jq -r '.names.venv' config.json 2>/dev/null)
    if [ "$VENV_NAME" = "null" ] || [ -z "$VENV_NAME" ]; then
        VENV_NAME="qai_hub" # default fallback name
    fi
else
    VENV_NAME="qai_hub" # default fallback name
fi

### CHECK FOLDER STRUCTURE : ###

# Check directory structure :
echo
echo "==========================="
echo "Checking folder structure : "
echo "==========================="

# Function to check if path exists and return appropriate symbol with color :
check_status() {
    local path="$1"
    local type="$2"
    
    if [ "$type" = "file" ]; then
        if [ -f "$path" ]; then
            echo -e "${GREEN}✔${NC}"
            return 0
        else
            echo -e "${RED}✗${NC}"
            return 1
        fi
    elif [ "$type" = "directory" ]; then
        if [ -d "$path" ]; then
            echo -e "${GREEN}✔${NC}"
            return 0
        else
            echo -e "${RED}✗${NC}"
            return 1
        fi
    fi
}

# Function to get colored name based on status :
get_colored_name() {
    local path="$1"
    local type="$2"
    local name="$3"
    
    if [ "$type" = "file" ]; then
        if [ -f "$path" ]; then
            echo "$name"
        else
            echo -e "${RED}$name${NC}"
        fi
    elif [ "$type" = "directory" ]; then
        if [ -d "$path" ]; then
            echo "$name"
        else
            echo -e "${RED}$name${NC}"
        fi
    fi
}

# Track missing items :
missing_items=()

echo
echo "┌────────────────┐"
echo "│ \$QUALCOMM_ROOT │"
echo "├────────────────┘"
echo "│"

# Check scripts directory
scripts_status=$(check_status "$QUALCOMM_ROOT/scripts" "directory")
scripts_name=$(get_colored_name "$QUALCOMM_ROOT/scripts" "directory" "scripts")
echo "├── $scripts_status $scripts_name"

if [ -d "$QUALCOMM_ROOT/scripts" ]; then
    config_status=$(check_status "$QUALCOMM_ROOT/scripts/config.json" "file")
    config_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/config.json" "file" "config.json")
    echo "│   ├── $config_status $config_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/config.json" ] && missing_items+=("config.json")
    
    setup_status=$(check_status "$QUALCOMM_ROOT/scripts/environment_setup.sh" "file")
    setup_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/environment_setup.sh" "file" "environment_setup.sh")
    echo "│   ├── $setup_status $setup_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/environment_setup.sh" ] && missing_items+=("environment_setup.sh")
    
    manage_status=$(check_status "$QUALCOMM_ROOT/scripts/manage_project.sh" "file")
    manage_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/manage_project.sh" "file" "manage_project.sh")
    echo "│   ├── $manage_status $manage_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/manage_project.sh" ] && missing_items+=("manage_project.sh")
    
    compile_status=$(check_status "$QUALCOMM_ROOT/scripts/compile.sh" "file")
    compile_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/compile.sh" "file" "compile.sh")
    echo "│   ├── $compile_status $compile_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/compile.sh" ] && missing_items+=("compile.sh")
    
    convert_status=$(check_status "$QUALCOMM_ROOT/scripts/convert.sh" "file")
    convert_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/convert.sh" "file" "convert.sh")
    echo "│   ├── $convert_status $convert_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/convert.sh" ] && missing_items+=("convert.sh")
    
    create_list_status=$(check_status "$QUALCOMM_ROOT/scripts/create_list.sh" "file")
    create_list_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/create_list.sh" "file" "create_list.sh")
    echo "│   ├── $create_list_status $create_list_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/create_list.sh" ] && missing_items+=("create_list.sh")
    
    batch_inference_status=$(check_status "$QUALCOMM_ROOT/scripts/batch_inference.sh" "file")
    batch_inference_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/batch_inference.sh" "file" "batch_inference.sh")
    echo "│   ├── $batch_inference_status $batch_inference_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/batch_inference.sh" ] && missing_items+=("batch_inference.sh")
    
    qnn_inference_status=$(check_status "$QUALCOMM_ROOT/scripts/qnn_inference.sh" "file")
    qnn_inference_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/qnn_inference.sh" "file" "qnn_inference.sh")
    echo "│   ├── $qnn_inference_status $qnn_inference_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/qnn_inference.sh" ] && missing_items+=("qnn_inference.sh")
    
    qnn_pull_status=$(check_status "$QUALCOMM_ROOT/scripts/qnn_pull.sh" "file")
    qnn_pull_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/qnn_pull.sh" "file" "qnn_pull.sh")
    echo "│   ├── $qnn_pull_status $qnn_pull_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/qnn_pull.sh" ] && missing_items+=("qnn_pull.sh")
    
    extract_metrics_status=$(check_status "$QUALCOMM_ROOT/scripts/extract_metrics.sh" "file")
    extract_metrics_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/extract_metrics.sh" "file" "extract_metrics.sh")
    echo "│   ├── $extract_metrics_status $extract_metrics_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/extract_metrics.sh" ] && missing_items+=("extract_metrics.sh")
    
    qnn_log_parser_status=$(check_status "$QUALCOMM_ROOT/scripts/qnn_log_parser.py" "file")
    qnn_log_parser_name=$(get_colored_name "$QUALCOMM_ROOT/scripts/qnn_log_parser.py" "file" "qnn_log_parser.py")
    echo "│   └── $qnn_log_parser_status $qnn_log_parser_name"
    [ ! -f "$QUALCOMM_ROOT/scripts/qnn_log_parser.py" ] && missing_items+=("qnn_log_parser.py")
else
    echo -e "│   ├── ${RED}✗ config.json${NC}"
    echo -e "│   ├── ${RED}✗ environment_setup.sh${NC}"
    echo -e "│   ├── ${RED}✗ manage_project.sh${NC}"
    echo -e "│   ├── ${RED}✗ compile.sh${NC}"
    echo -e "│   ├── ${RED}✗ convert.sh${NC}"
    echo -e "│   ├── ${RED}✗ create_list.sh${NC}"
    echo -e "│   ├── ${RED}✗ batch_inference.sh${NC}"
    echo -e "│   ├── ${RED}✗ qnn_inference.sh${NC}"
    echo -e "│   ├── ${RED}✗ qnn_pull.sh${NC}"
    echo -e "│   ├── ${RED}✗ extract_metrics.sh${NC}"
    echo -e "│   └── ${RED}✗ qnn_log_parser.py${NC}"
    missing_items+=("scripts directory")
fi

# Check environment directory :
env_status=$(check_status "$QUALCOMM_ROOT/environment" "directory")
env_name=$(get_colored_name "$QUALCOMM_ROOT/environment" "directory" "environment")
echo "├── $env_status $env_name"

if [ -d "$QUALCOMM_ROOT/environment" ]; then
    # Check sdks
    sdks_status=$(check_status "$QUALCOMM_ROOT/environment/sdks" "directory")
    sdks_name=$(get_colored_name "$QUALCOMM_ROOT/environment/sdks" "directory" "sdks")
    echo "│   ├── $sdks_status $sdks_name"
    
    if [ -d "$QUALCOMM_ROOT/environment/sdks" ]; then
        qnn_status=$(check_status "$QUALCOMM_ROOT/environment/sdks/qnn" "directory")
        qnn_name=$(get_colored_name "$QUALCOMM_ROOT/environment/sdks/qnn" "directory" "qnn")
        echo "│   │   ├── $qnn_status $qnn_name"
        [ ! -d "$QUALCOMM_ROOT/environment/sdks/qnn" ] && missing_items+=("qnn directory")
        
        toolchains_status=$(check_status "$QUALCOMM_ROOT/environment/sdks/toolchains" "directory")
        toolchains_name=$(get_colored_name "$QUALCOMM_ROOT/environment/sdks/toolchains" "directory" "toolchains")
        echo "│   │   ├── $toolchains_status $toolchains_name"
        [ ! -d "$QUALCOMM_ROOT/environment/sdks/toolchains" ] && missing_items+=("toolchains directory")
        
        wayland_status=$(check_status "$QUALCOMM_ROOT/environment/sdks/qcom_wayland_sdk" "directory")
        wayland_name=$(get_colored_name "$QUALCOMM_ROOT/environment/sdks/qcom_wayland_sdk" "directory" "qcom_wayland_sdk")
        echo "│   │   └── $wayland_status $wayland_name"
        [ ! -d "$QUALCOMM_ROOT/environment/sdks/qcom_wayland_sdk" ] && missing_items+=("qcom_wayland_sdk directory")
    else
        echo -e "│   │   ├── ${RED}✗ qnn${NC}"
        echo -e "│   │   ├── ${RED}✗ toolchains${NC}"
        echo -e "│   │   └── ${RED}✗ qcom_wayland_sdk${NC}"
        missing_items+=("sdks directory")
    fi
    
    # Check virtual_environments :
    venv_dir_status=$(check_status "$QUALCOMM_ROOT/environment/virtual_environments" "directory")
    venv_dir_name=$(get_colored_name "$QUALCOMM_ROOT/environment/virtual_environments" "directory" "virtual_environments")
    echo "│   └── $venv_dir_status $venv_dir_name"
    
    if [ -d "$QUALCOMM_ROOT/environment/virtual_environments" ]; then
        venv_status=$(check_status "$QUALCOMM_ROOT/environment/virtual_environments/$VENV_NAME" "directory")
        venv_name=$(get_colored_name "$QUALCOMM_ROOT/environment/virtual_environments/$VENV_NAME" "directory" "$VENV_NAME")
        echo "│       └── $venv_status $venv_name"
        [ ! -d "$QUALCOMM_ROOT/environment/virtual_environments/$VENV_NAME" ] && missing_items+=("$VENV_NAME virtual environment")
    else
        echo -e "│       └── ${RED}✗ $VENV_NAME${NC}"
        missing_items+=("virtual_environments directory")
    fi
else
    echo -e "│   ├── ${RED}✗ sdks${NC}"
    echo -e "│   │   ├── ${RED}✗ qnn${NC}"
    echo -e "│   │   ├── ${RED}✗ toolchains${NC}"
    echo -e "│   │   └── ${RED}✗ qcom_wayland_sdk${NC}"
    echo -e "│   └── ${RED}✗ virtual_environments${NC}"
    echo -e "│       └── ${RED}✗ $VENV_NAME${NC}"
    missing_items+=("environment directory")
fi

# Check projects directory :
projects_status=$(check_status "$QUALCOMM_ROOT/projects" "directory")
projects_name=$(get_colored_name "$QUALCOMM_ROOT/projects" "directory" "projects")
echo "└── $projects_status $projects_name"

if [ -d "$QUALCOMM_ROOT/projects" ]; then
    # Get project name from config.json if available :
    if [ -f "config.json" ]; then
        PROJECT_NAME=$(jq -r '.names.project' config.json 2>/dev/null)
        if [ "$PROJECT_NAME" != "null" ] && [ -n "$PROJECT_NAME" ]; then
            project_status=$(check_status "$QUALCOMM_ROOT/projects/$PROJECT_NAME" "directory")
            project_name=$(get_colored_name "$QUALCOMM_ROOT/projects/$PROJECT_NAME" "directory" "$PROJECT_NAME")
            echo "    └── $project_status $project_name"
            
            if [ -d "$QUALCOMM_ROOT/projects/$PROJECT_NAME" ]; then
                models_status=$(check_status "$QUALCOMM_ROOT/projects/$PROJECT_NAME/models" "directory")
                models_name=$(get_colored_name "$QUALCOMM_ROOT/projects/$PROJECT_NAME/models" "directory" "models")
                echo "        ├── $models_status $models_name"
                [ ! -d "$QUALCOMM_ROOT/projects/$PROJECT_NAME/models" ] && missing_items+=("models directory")
                
                data_status=$(check_status "$QUALCOMM_ROOT/projects/$PROJECT_NAME/data" "directory")
                data_name=$(get_colored_name "$QUALCOMM_ROOT/projects/$PROJECT_NAME/data" "directory" "data")
                echo "        ├── $data_status $data_name"
                [ ! -d "$QUALCOMM_ROOT/projects/$PROJECT_NAME/data" ] && missing_items+=("data directory")
                
                outputs_status=$(check_status "$QUALCOMM_ROOT/projects/$PROJECT_NAME/outputs" "directory")
                outputs_name=$(get_colored_name "$QUALCOMM_ROOT/projects/$PROJECT_NAME/outputs" "directory" "outputs")
                echo "        └── $outputs_status $outputs_name"
                [ ! -d "$QUALCOMM_ROOT/projects/$PROJECT_NAME/outputs" ] && missing_items+=("outputs directory")
            else
                echo -e "        ├── ${RED}✗ models${NC}"
                echo -e "        ├── ${RED}✗ data${NC}"
                echo -e "        └── ${RED}✗ outputs${NC}"
                missing_items+=("$PROJECT_NAME project directory")
            fi
        else
            echo -e "    └── ${YELLOW}⚠ Could not read project name from config.json${NC}"
            missing_items+=("project name in config.json")
        fi
    else
        echo -e "    └── ${RED}✗ {project_name}${NC}"
        echo -e "        ├── ${RED}✗ models${NC}"
        echo -e "        ├── ${RED}✗ data${NC}"
        echo -e "        └── ${RED}✗ outputs${NC}"
        missing_items+=("config.json not found")
    fi
else
    echo -e "    └── ${RED}✗ {project_name}${NC}"
    echo -e "        ├── ${RED}✗ models${NC}"
    echo -e "        ├── ${RED}✗ data${NC}"
    echo -e "        └── ${RED}✗ outputs${NC}"
    missing_items+=("projects directory")
fi

# Display results :
echo
if [ ${#missing_items[@]} -eq 0 ]; then
    echo -e "# ${GREEN}✔ All required directories and files are present${NC}"
else
    echo -e "# ${RED}⚠ Missing items found:${NC}"
    for item in "${missing_items[@]}"; do
        echo -e "#   - $item"
    done
    echo
    echo -e "# ${RED}Structure broken, consider re-installing the environment${NC}"
    echo
    read -p "Continue environment check ? Unexpected errors may happen ! (y/n) : " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    	echo
        echo "----- Environment checking is done -----"
        echo
        
        # Create a temporary startup file that deactivates any venv for the interactive bash :
        temp_rcfile=$(mktemp)
        cat > "$temp_rcfile" << EOF
[ -f ~/.bashrc ] && source ~/.bashrc
deactivate 2>/dev/null || true
PS1="\$PS1"
EOF
        
        # Start interactive bash :
        exec bash --rcfile "$temp_rcfile"
    fi
fi

### CHECK PACKAGES : ###

echo
echo "==================="
echo "Checking packages : "
echo "==================="

missing_packages=()
installed_packages=()

# Find the longest package name :
max_package_length=0
for package in "${packages[@]}"; do
    # Truncate package name if it exceeds max length :
    display_name="$package"
    if [ ${#package} -gt $MAX_PACKAGE_LENGTH ]; then
        display_name="${package:0:$((MAX_PACKAGE_LENGTH-3))}..."
    fi
    
    if [ ${#display_name} -gt $max_package_length ]; then
        max_package_length=${#display_name}
    fi
done

# Create separator line :
package_separator_length=$((max_package_length + 8))
package_separator=$(printf '%*s' "$package_separator_length" '' | tr ' ' '-')

# Display chart :
echo
echo "$package_separator"

for package in "${packages[@]}"; do

    # Truncate package name if it exceeds max length :
    display_name="$package"
    if [ ${#package} -gt $MAX_PACKAGE_LENGTH ]; then
        display_name="${package:0:$((MAX_PACKAGE_LENGTH-3))}..."
    fi
    
    # Compute needed padding for fixed length lines :
    padding=$((max_package_length - ${#display_name}))
    spaces=$(printf '%*s' "$padding" '')
    
    # Check package and display line :
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "ok installed"; then
        echo -e "| ${GREEN}✔${NC} | $display_name$spaces |"
        installed_packages+=("$package")
    else
        echo -e "| ${RED}✗${NC} | ${RED}$display_name${NC}$spaces |"
        missing_packages+=("$package")
    fi
done

echo "$package_separator"
echo

if [ ${#missing_packages[@]} -gt 0 ]; then
    echo -e "# ${RED}⚠ Missing packages :${NC}"
    echo "# ${#missing_packages[@]}"
    echo "# Install missing packages with :"
    echo "# sudo apt update && sudo apt install ${missing_packages[*]}"
    
else
    echo -e "# ${GREEN}✔ All packages are correctly installed${NC}"
fi

### CHECK PYTHON ENVIRONMENT : ###

echo
echo "============================="
echo "Checking Python environment :"
echo "============================="

# Fetch venv name from config.json :
VENV_NAME=$(jq -r '.names.venv' config.json 2>/dev/null)
if [ "$VENV_NAME" = "null" ] || [ -z "$VENV_NAME" ]; then
    VENV_NAME="qai_hub"  # Use the same fallback as earlier
fi
VENV_FULL_PATH=$QUALCOMM_ROOT/environment/virtual_environments/$VENV_NAME

# Check and display venv name :
echo
echo "Virtual environment setup :"

if [ "$VENV_NAME" = "null" ] || [ -z "$VENV_NAME" ]; then
   echo -e "# ${RED}⚠ Could not fetch venv name from config.json${NC}"
   
elif [ ! -d "$VENV_FULL_PATH" ]; then
   echo -e "# ${RED}⚠ No virtual environment found at : $VENV_FULL_PATH${NC}"
   
else
    echo "# Name : $VENV_NAME"
    echo "# Path : $QUALCOMM_ROOT/environment/virtual_environments/$VENV_NAME"
    
    # Try to activate the virtual environment :
    echo
    echo "Activating virtual environment..."
    source "$QUALCOMM_ROOT/environment/virtual_environments/$VENV_NAME/bin/activate"
    
    if [ $? -ne 0 ]; then
        echo -e "# ${RED}⚠ Failed to activate virtual environment${NC}"
        
    fi
    
    echo -e "# ${GREEN}✔ Virtual environment $VENV_NAME activated${NC}"
    
    # Check Python version :
    echo
    echo "Checking Python version..."
    
    python_version=$(python --version 2>&1 | cut -d' ' -f2)
    major_minor=$(echo $python_version | cut -d'.' -f1,2)
    
    if [ "$major_minor" != "3.10" ]; then
        echo -e "# ${RED}⚠ Python version is incorrect : $python_version \(expected 3.10.x\)${NC}"
        deactivate
        
    else
        echo -e "# ${GREEN}✔ Python version is correct : $python_version${NC}"
    fi
    
    # Check if required libraries are installed with correct versions :
    echo
    echo "Checking libraries..."
    
    missing_libs=()
    wrong_version_libs=()
    
    # Find the longest library name :
    max_library_length=0
    for library in "${REQUIRED_LIBRARIES[@]}"; do
        # Truncate library name if it exceeds max length :
        display_name="$REQUIRED_LIBRARIES"
        if [ ${#REQUIRED_LIBRARIES} -gt $MAX_LIBRARY_LENGTH ]; then
            display_name="${REQUIRED_LIBRARIES:0:$((MAX_LIBRARY_LENGTH-3))}..."
        fi
    
        if [ ${#display_name} -gt $max_library_length ]; then
            max_library_length=${#display_name}
        fi
    done

    # Create separator line :
    library_separator_length=$((max_library_length + 8))
    library_separator=$(printf '%*s' "$library_separator_length" '' | tr ' ' '-')
    
    # Check libraries :
    echo
    echo "$library_separator"  
      
    for lib_spec in "${REQUIRED_LIBRARIES[@]}"; do
    	
    	# Extract infos (name and required version) :
    	IFS=':' read -r lib_name required_version <<< "$lib_spec"
    
        # Truncate library name if it exceeds max length :
        display_name="$lib_name"
        if [ ${#lib_name} -gt $MAX_LIBRARY_LENGTH ]; then
            display_name="${lib_name:0:$((MAX_LIBRARY_LENGTH-3))}..."
        fi
    
        # Compute needed padding for fixed length lines :
        padding=$((max_library_length - ${#display_name}))
        spaces=$(printf '%*s' "$padding" '')
        
        # Check library and display line :
        if ! timeout 10s python -c "import $lib_name" &>/dev/null; then
            missing_libs+=("$lib_spec")
            echo -e "| ${RED}✗${NC} | ${RED}$display_name${NC}$spaces |"
        else
            # If version matters, check it :
            if [ "$required_version" != "None" ]; then
                # Handle special cases for version detection :
                case "$lib_name" in
                    "tflite")
                        # tflite doesn't have __version__, check if it imports successfully :
                        echo -e "| ${GREEN}✔${NC} | $display_name$spaces |"
                        ;;
                    "torch"|"torchvision"|"torchaudio")
                        # PyTorch libraries may have +cpu suffix :
                        installed_version=$(timeout 10s python -c "import $lib_name; print($lib_name.__version__)" 2>/dev/null)
                        if [ -z "$installed_version" ]; then
                            missing_libs+=("$lib_spec")
                            echo -e "| ${RED}✗${NC} | ${RED}$display_name${NC}$spaces |"
                        else
                            # Remove +cpu suffix for comparison :
                            clean_installed_version=$(echo "$installed_version" | sed 's/+.*$//')
                            if [ "$clean_installed_version" != "$required_version" ]; then
                                echo -e "| ${YELLOW}⚠${NC} | ${YELLOW}$display_name${NC}$spaces |"
                                wrong_version_libs+=("$lib_name:$installed_version \(required: $required_version\)")
                                missing_libs+=("$lib_spec")
                            else
                                echo -e "| ${GREEN}✔${NC} | $display_name$spaces |"
                            fi
                        fi
                        ;;
                    *)
                        # Standard version check for other libraries :
                        installed_version=$(timeout 10s python -c "import $lib_name; print($lib_name.__version__)" 2>/dev/null)
                        if [ -z "$installed_version" ]; then
                            # Library exists but no version info :
                            echo -e "| ${GREEN}✔${NC} | $display_name$spaces |"
                        elif [ "$installed_version" != "$required_version" ]; then
                            echo -e "| ${YELLOW}⚠${NC} | ${YELLOW}$display_name${NC}$spaces |"
                            wrong_version_libs+=("$lib_name:$installed_version \(required: $required_version\)")
                            missing_libs+=("$lib_spec")
                        else
                            echo -e "| ${GREEN}✔${NC} | $display_name$spaces |"
                        fi
                        ;;
                esac
            else
                echo -e "| ${GREEN}✔${NC} | $display_name$spaces |"
            fi
        fi
    done
    
    echo "$library_separator"  
    echo
    
    # Display conclusion :
    if [ ${#missing_libs[@]} -eq 0 ] && [ ${#wrong_version_libs[@]} -eq 0 ]; then
        echo -e "# ${GREEN}✔ All required libraries are installed with correct versions${NC}"
    else
        echo -e "# ${RED}⚠ Issues found with libraries:${NC}"
        
        # Show missing libraries :
        for lib_spec in "${missing_libs[@]}"; do
            IFS=':' read -r lib_name required_version <<< "$lib_spec"
            
            # Check if it's completely missing or wrong version :
            if ! python -c "import $lib_name" &>/dev/null; then
                echo -e "#   - ${RED}✗ $lib_name${NC} : MISSING"
            else
                # Version mismatch :
                installed_version=$(python -c "import $lib_name; print($lib_name.__version__)" 2>/dev/null)
                echo -e "#   - ${YELLOW}⚠ $lib_name${NC} : installed $installed_version, expected $required_version"
            fi
        done
        
	echo
        echo "# Install missing/incorrect libraries with :"
        
        # Check if any PyTorch libraries are missing :
        pytorch_libs=()
        other_libs=()
        
        for lib_spec in "${missing_libs[@]}"; do
            IFS=':' read -r lib_name required_version <<< "$lib_spec"
            
            if [[ "$lib_name" =~ ^(torch|torchvision|torchaudio)$ ]]; then
                if [ "$required_version" = "None" ]; then
                    pytorch_libs+=("$lib_name")
                else
                    # For newer PyTorch versions, don't add +cpu suffix :
                    pytorch_libs+=("$lib_name==$required_version")
                fi
            else
                if [ "$required_version" = "None" ]; then
                    other_libs+=("$lib_name")
                else
                    other_libs+=("$lib_name==$required_version")
                fi
            fi
        done
        
        # Install PyTorch libraries (newer versions don't need special index) :
        if [ ${#pytorch_libs[@]} -gt 0 ]; then
            echo -n "# pip install "
            printf "%s " "${pytorch_libs[@]}"
            echo
        fi
        
        # Install other libraries normally :
        if [ ${#other_libs[@]} -gt 0 ]; then
            echo -n "# pip install "
            printf "%s " "${other_libs[@]}"
            echo
        fi
        echo
    fi
    
    echo -e "# ${GREEN}✔ Virtual environment setup complete${NC}"
fi

### SETUP TOOLCHAINS : ###

# Source toolchain environment setup :
TOOLCHAIN_SETUP="$QUALCOMM_ROOT/environment/sdks/qcom_wayland_sdk/environment-setup-armv8-2a-qcom-linux"

echo
echo "=================================="
echo "Setting up toolchain environment :"
echo "=================================="

echo
echo "Sourcing toolchain environment..."
echo

if [ -f "$TOOLCHAIN_SETUP" ]; then
    source "$TOOLCHAIN_SETUP" &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "# ${GREEN}✔ Toolchain environment sourced successfully${NC}"
    else
        echo -e "# ${RED}⚠ Failed to source toolchain environment${NC}"
    fi
else
    echo -e "# ${RED}⚠ Toolchain setup file not found: $TOOLCHAIN_SETUP${NC}"
fi

### SETUP AI HUB : ###

echo
echo "====================="
echo "Configuring AI Hub :"
echo "====================="

# Fetch API token from config.json :
API_TOKEN=$(jq -r '.variables.api_token' config.json)

# Set up the AI Hub :
if [ "$API_TOKEN" != "null" ] && [ -n "$API_TOKEN" ]; then
    echo
    echo "Configuring qai-hub with API token..."
    echo
    
    qai-hub configure --api_token "$API_TOKEN" &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "# ${GREEN}✔ qai-hub configured successfully${NC}"
    else
        echo -e "# ${RED}⚠ Failed to configure qai-hub${NC}"
    fi
else
    echo -e "# ${RED}⚠ Could not fetch API token from config.json${NC}"
fi

### EXPORT ENVIRONMENT VARIABLES : ###

echo
echo "================================="
echo "Exporting environment variables :"
echo "================================="
echo

# Source environment setup file :
source $QNN_SDK_ROOT/bin/envsetup.sh &>/dev/null

# Export variables from environment_variables section :
export SNPE_ROOT=$(jq -r '.environment_variables.SNPE_ROOT' config.json | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
export QNN_ROOT=$(jq -r '.environment_variables.QNN_ROOT' config.json | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")
export ESDK_ROOT=$(jq -r '.environment_variables.ESDK_ROOT' config.json | sed "s|\$QUALCOMM_ROOT|$QUALCOMM_ROOT|g")

# Get project name and create PROJECT_ROOT :
PROJECT_NAME=$(jq -r '.names.project' config.json)
export PROJECT_ROOT="$QUALCOMM_ROOT/projects/$PROJECT_NAME"

# Display exported variables :
echo -e "# Environment variables exported :"
echo "#   - SNPE_ROOT = $SNPE_ROOT"
echo "#   - QNN_ROOT = $QNN_ROOT"
echo "#   - ESDK_ROOT = $ESDK_ROOT"
echo "#   - PROJECT_ROOT = $PROJECT_ROOT"

# Validate that the paths exist :
missing_paths=()
if [ ! -d "$SNPE_ROOT" ]; then
    missing_paths+=("SNPE_ROOT: $SNPE_ROOT")
fi
if [ ! -d "$QNN_ROOT" ]; then
    missing_paths+=("QNN_ROOT: $QNN_ROOT")
fi
if [ ! -d "$ESDK_ROOT" ]; then
    missing_paths+=("ESDK_ROOT: $ESDK_ROOT")
fi
if [ ! -d "$PROJECT_ROOT" ]; then
    missing_paths+=("PROJECT_ROOT: $PROJECT_ROOT")
fi

# Display conclusion :
echo
if [ ${#missing_paths[@]} -gt 0 ]; then
    echo -e "# ${YELLOW}⚠ Warning: Some environment paths do not exist:${NC}"
    for path in "${missing_paths[@]}"; do
        echo -e "#   - $path"
    done
else
    echo -e "# ${GREEN}✔ All environment paths verified${NC}"
fi

### CREATE SYMLINKS : ###

echo
echo "==================="
echo "Creating symlinks :"
echo "==================="
echo

# Debug function to check what exists :
debug_paths() {
    echo "Debugging ESDK structure..."
    echo "ESDK_ROOT: $ESDK_ROOT"
    echo
    
    # Check what actually exists :
    local base_path="$ESDK_ROOT/tmp/sysroots"
    echo "Contents of $base_path:"
    if [ -d "$base_path" ]; then
        ls -la "$base_path"
    else
        echo "  Directory does not exist"
    fi
    echo
    
    # Check x86_64-qtisdk-linux structure :
    local x86_path="$base_path/x86_64-qtisdk-linux"
    echo "Checking $x86_path:"
    if [ -e "$x86_path" ]; then
        echo "  Exists ($([ -L "$x86_path" ] && echo "symlink" || echo "$([ -d "$x86_path" ] && echo "directory" || echo "file")"))"
        if [ -d "$x86_path" ] || [ -L "$x86_path" ]; then
            echo "  Contents:"
            ls -la "$x86_path" 2>/dev/null | head -10
        fi
    else
        echo "  Does not exist"
    fi
    echo
}

# Function to create symbolic link and check success :
create_symlink() {
    local source="$1"
    local target="$2"
    
    echo "Creating symlink : $target -> $source"
    
    # Check if target already exists :
    if [ -L "$target" ]; then
        echo -e "  ${YELLOW}⚠${NC} Symlink already exists, removing old one"
        rm "$target"
    elif [ -e "$target" ]; then
        echo -e "  ${YELLOW}⚠${NC} Target exists, removing to recreate: $target"
        rm -rf "$target"
    fi
    
    # Get the parent directory :
    local target_dir=$(dirname "$target")
    
    # Ensure parent directory exists :
    if [ ! -e "$target_dir" ]; then
        echo "  Creating parent directory : $target_dir"
        if ! mkdir -p "$target_dir" 2>/dev/null; then
            echo -e "  ${RED}✗${NC} Cannot create directory : $target_dir"
            return 1
        fi
    fi
    
    # Create the symlink :
    if ln -s "$source" "$target" 2>/dev/null; then
        echo -e "  ${GREEN}✔${NC} Symlink created successfully"
        return 0
    else
        echo -e "  ${RED}✗${NC} Failed to create symlink"
        return 1
    fi
}

failed_operations=0

echo "Setting up ESDK symbolic links..."
echo

# First, create the basic symlinks :
create_symlink "$ESDK_ROOT/tmp/sysroots/qcm6490" "$ESDK_ROOT/tmp/sysroots/armv8a-oe-linux"
[ $? -ne 0 ] && ((failed_operations++))
echo

create_symlink "$ESDK_ROOT/tmp/sysroots/x86_64" "$ESDK_ROOT/tmp/sysroots/x86_64-qtisdk-linux"
[ $? -ne 0 ] && ((failed_operations++))
echo

# Now check what's actually in the x86_64 directory :
echo "Checking contents of x86_64 directory..."
if [ -d "$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin" ]; then
    echo "  usr/bin exists, checking for aarch64-qcom-linux..."
    if [ -d "$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin/aarch64-qcom-linux" ]; then
        echo -e "  ${GREEN}✔${NC} aarch64-qcom-linux directory exists"
        
        # Create the aarch64-oe-linux symlink :
        create_symlink "aarch64-qcom-linux" "$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin/aarch64-oe-linux"
        [ $? -ne 0 ] && ((failed_operations++))
        echo
        
        # Set the binary directory path :
        qcom_bin_dir="$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin/aarch64-qcom-linux"
        
        
        
        # Check and create symlinks for each binary :
        if [ -f "$qcom_bin_dir/aarch64-qcom-linux-g++" ]; then
            echo -e "  ${GREEN}✔${NC} Found aarch64-qcom-linux-g++"
            create_symlink "aarch64-qcom-linux-g++" "$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin/aarch64-oe-linux/aarch64-oe-linux-g++"
            [ $? -ne 0 ] && ((failed_operations++))
            echo
        else
            echo -e "  ${RED}✗${NC} aarch64-qcom-linux-g++ not found in $qcom_bin_dir"
            ((failed_operations++))
        fi
        
        if [ -f "$qcom_bin_dir/aarch64-qcom-linux-objdump" ]; then
            echo -e "  ${GREEN}✔${NC} Found aarch64-qcom-linux-objdump"
            create_symlink "aarch64-qcom-linux-objdump" "$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin/aarch64-oe-linux/aarch64-oe-linux-objdump"
            [ $? -ne 0 ] && ((failed_operations++))
            echo
        else
            echo -e "  ${RED}✗${NC} aarch64-qcom-linux-objdump not found in $qcom_bin_dir"
            ((failed_operations++))
        fi
        
        if [ -f "$qcom_bin_dir/aarch64-qcom-linux-objcopy" ]; then
            echo -e "  ${GREEN}✔${NC} Found aarch64-qcom-linux-objcopy"
            create_symlink "aarch64-qcom-linux-objcopy" "$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin/aarch64-oe-linux/aarch64-oe-linux-objcopy"
            [ $? -ne 0 ] && ((failed_operations++))
            echo
        else
            echo -e "  ${RED}✗${NC} aarch64-qcom-linux-objcopy not found in $qcom_bin_dir"
            ((failed_operations++))
        fi
        
    else
        echo -e "  ${RED}✗${NC} aarch64-qcom-linux directory not found"
        echo "  Available contents in usr/bin:"
        ls -la "$ESDK_ROOT/tmp/sysroots/x86_64/usr/bin/" | head -10
        failed_operations=$((failed_operations + 4))
    fi
else
    echo -e "  ${RED}✗${NC} usr/bin directory not found in x86_64"
    failed_operations=$((failed_operations + 4))
fi

# Export environment variable :
echo "Exporting QNN_AARCH64_LINUX_OE_GCC_112..."
export QNN_AARCH64_LINUX_OE_GCC_112="$ESDK_ROOT/tmp/"
echo -e "${GREEN}✔${NC} Exported QNN_AARCH64_LINUX_OE_GCC_112=$QNN_AARCH64_LINUX_OE_GCC_112"
echo

# Display conclusion :
if [ $failed_operations -eq 0 ]; then
    echo -e "# ${GREEN}✔ All symbolic links created successfully${NC}"
else
    echo -e "# ${RED}⚠ $failed_operations symbolic link operation(s) failed${NC}"
fi

### FINISH SETUP : ###

echo
echo "----- Environment checking is done -----"
echo

# Create a temporary startup file that activates the venv for the interactive bash :
temp_rcfile=$(mktemp)
cat > "$temp_rcfile" << EOF
source '$VENV_FULL_PATH/bin/activate'
source '$TOOLCHAIN_SETUP' &>/dev/null
source '$QNN_SDK_ROOT/bin/envsetup.sh' &>/dev/null
[ -f ~/.bashrc ] && source ~/.bashrc
PS1="($VENV_NAME) \$PS1"
EOF

# Start interactive bash :
exec bash --rcfile "$temp_rcfile"

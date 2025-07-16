#!/bin/bash

# Manage project structures with create, delete, and rename operations

### PARAMETERS : ###

# Colors for output :
RED='\033[38;2;220;50;47m'
GREEN='\033[38;2;0;200;0m'
YELLOW='\033[38;2;255;193;7m'
BLUE='\033[38;2;0;123;255m'
NC='\033[0m' # no color

# Script configuration :
SCRIPT_NAME="manage_project.sh"
VERSION="2.0.0"

# Function to display help :
show_help() {
    cat << EOF

${BLUE}Project Management Tool v$VERSION${NC}
${BLUE}==================================${NC}

${GREEN}DESCRIPTION:${NC}
    Manages QNN project structures with create, delete, rename, restore, and 
    set-active operations. Handles project directory structure and maintains 
    active project configuration in config.json.

${GREEN}USAGE:${NC}
    $SCRIPT_NAME <COMMAND> [OPTIONS]

${GREEN}COMMANDS:${NC}
    ${YELLOW}create${NC}              Create a new project structure
    ${YELLOW}delete${NC}              Delete an existing project structure  
    ${YELLOW}rename${NC}              Rename an existing project structure
    ${YELLOW}restore${NC}             Restore a project from backup
    ${YELLOW}set-active${NC}          Set or clear the active project

${GREEN}GLOBAL OPTIONS:${NC}
    ${YELLOW}-h, --help${NC}          Show this help message

${GREEN}CREATE COMMAND:${NC}
    $SCRIPT_NAME create -n PROJECT_NAME [OPTIONS]
    
    ${YELLOW}Required:${NC}
        ${YELLOW}-n, --name NAME${NC}       Project name to create
    
    ${YELLOW}Optional:${NC}
        ${YELLOW}-a, --active${NC}          Set created project as active in config.json
    
    ${YELLOW}Examples:${NC}
        $SCRIPT_NAME create -n rail_detection
        $SCRIPT_NAME create --name yolo_inference --active

${GREEN}DELETE COMMAND:${NC}
    $SCRIPT_NAME delete -n PROJECT_NAME [OPTIONS]
    
    ${YELLOW}Required:${NC}
        ${YELLOW}-n, --name NAME${NC}       Project name to delete
    
    ${YELLOW}Optional:${NC}
        ${YELLOW}-a, --active NAME${NC}     Set different project as active after deletion
        ${YELLOW}-b${NC}                   Create backup before deletion
    
    ${YELLOW}Examples:${NC}
        $SCRIPT_NAME delete -n old_project
        $SCRIPT_NAME delete --name old_project --active new_project -b

${GREEN}RENAME COMMAND:${NC}
    $SCRIPT_NAME rename -n OLD_NAME -nn NEW_NAME [OPTIONS]
    
    ${YELLOW}Required:${NC}
        ${YELLOW}-n, --name NAME${NC}       Current project name
        ${YELLOW}-nn, --new-name NAME${NC}  New project name
    
    ${YELLOW}Optional:${NC}
        ${YELLOW}-a, --active${NC}          Update active project to new name
        ${YELLOW}-b${NC}                   Create backup before rename
    
    ${YELLOW}Examples:${NC}
        $SCRIPT_NAME rename -n old_name -nn new_name
        $SCRIPT_NAME rename --name project1 --new-name project2 --active -b

${GREEN}RESTORE COMMAND:${NC}
    $SCRIPT_NAME restore -n BACKUP_NAME [OPTIONS]
    
    ${YELLOW}Required:${NC}
        ${YELLOW}-n, --name NAME${NC}       Backup name to restore (without BACKUP_ prefix)
    
    ${YELLOW}Optional:${NC}
        ${YELLOW}-nn, --new-name NAME${NC}  Restore with different name
        ${YELLOW}-a, --active${NC}          Set restored project as active
        ${YELLOW}-b${NC}                   Keep backup after restore (default: removes backup)
    
    ${YELLOW}Examples:${NC}
        $SCRIPT_NAME restore -n old_project
        $SCRIPT_NAME restore --name project1 --new-name project2 --active
        $SCRIPT_NAME restore -n old_project -b --active

${GREEN}SET-ACTIVE COMMAND:${NC}
    $SCRIPT_NAME set-active -n PROJECT_NAME
    $SCRIPT_NAME set-active --clear
    
    ${YELLOW}Options:${NC}
        ${YELLOW}-n, --name NAME${NC}       Project name to set as active
        ${YELLOW}--clear${NC}               Clear active project (no active project)
    
    ${YELLOW}Examples:${NC}
        $SCRIPT_NAME set-active -n my_project
        $SCRIPT_NAME set-active --name rail_detection
        $SCRIPT_NAME set-active --clear

${GREEN}PROJECT STRUCTURE:${NC}
    Projects are created with the following structure:
    \$QUALCOMM_ROOT/projects/PROJECT_NAME/
    ├── data/           # Input data, calibration files, lists
    ├── models/         # Model files (.onnx, .cpp, .bin, .so)
    └── outputs/        # Inference results and metrics

    ${YELLOW}Backups are stored at:${NC}
    \$QUALCOMM_ROOT/projects/backup/BACKUP_PROJECT_NAME/

${GREEN}PROJECT NAMING RULES:${NC}
    • Only alphanumeric characters, underscores, and hyphens allowed
    • Must start with letter or underscore
    • Maximum 50 characters
    • Examples: rail_detection, yolo_v8, model-comparison_2024

${GREEN}ACTIVE PROJECT:${NC}
    The active project is stored in config.json and used by other scripts.
    It sets the PROJECT_ROOT environment variable for the current session.

${GREEN}REQUIREMENTS:${NC}
    • QUALCOMM_ROOT environment variable must be set
    • config.json must exist in \$QUALCOMM_ROOT/scripts/
    • jq must be installed for JSON manipulation
    • Write permissions in \$QUALCOMM_ROOT/projects/

${GREEN}EXIT CODES:${NC}
    0    Success
    1    Error (missing arguments, invalid name, directory conflicts, etc.)

EOF
}

# Function to validate project name :
validate_project_name() {
    local name="$1"
    
    # Check if name is empty :
    if [ -z "$name" ]; then
        echo -e "${RED}Error : Project name cannot be empty${NC}" >&2
        return 1
    fi
    
    # Check if name contains only valid characters (alphanumeric, underscore, hyphen) :
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error : Project name can only contain letters, numbers, underscores, and hyphens${NC}" >&2
        return 1
    fi
    
    # Check if name is too long (reasonable limit) :
    if [ ${#name} -gt 50 ]; then
        echo -e "${RED}Error : Project name is too long (maximum 50 characters)${NC}" >&2
        return 1
    fi
    
    # Check if name starts with a letter or underscore (good practice) :
    if [[ ! "$name" =~ ^[a-zA-Z_] ]]; then
        echo -e "${RED}Error : Project name should start with a letter or underscore${NC}" >&2
        return 1
    fi
    
    return 0
}

# SET-ACTIVE command implementation :
cmd_set_active() {
    local project_name=""
    local clear_active=false
    
    # Parse set-active-specific arguments :
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Project name is required after $1${NC}" >&2
                    return 1
                fi
                project_name="$2"
                shift 2
                ;;
            --clear)
                clear_active=true
                shift
                ;;
            -nn|--new-name)
                echo -e "${RED}Error : --new-name is not valid for set-active command${NC}" >&2
                return 1
                ;;
            -a|--active)
                echo -e "${RED}Error : --active is not valid for set-active command${NC}" >&2
                return 1
                ;;
            -b)
                echo -e "${RED}Error : -b (backup) is not valid for set-active command${NC}" >&2
                return 1
                ;;
            *)
                echo -e "${RED}Error : Unknown option for set-active command : $1${NC}" >&2
                return 1
                ;;
        esac
    done
    
    # Validate arguments :
    if [ "$clear_active" = true ] && [ -n "$project_name" ]; then
        echo -e "${RED}Error : Cannot use both --clear and -n/--name options together${NC}" >&2
        return 1
    fi
    
    if [ "$clear_active" = false ] && [ -z "$project_name" ]; then
        echo -e "${RED}Error : Project name is required for set-active command${NC}" >&2
        echo "Use : $SCRIPT_NAME set-active -n <project_name>"
        echo "Or  : $SCRIPT_NAME set-active --clear"
        return 1
    fi
    
    # Get current active project :
    local current_active=$(get_active_project)
    
    if [ "$clear_active" = true ]; then
        echo "=========================================="
        echo "Clearing active project"
        echo "=========================================="
        echo
        
        if [ -z "$current_active" ]; then
            echo -e "${YELLOW}Warning : No active project is currently set${NC}"
            echo
            echo "=========================================="
            echo -e "${GREEN}✔ Active project status unchanged${NC}"
            echo "=========================================="
            echo
            return 0
        fi
        
        echo "Current active project : $current_active"
        echo "Clearing active project..."
        
        if ! update_active_project ""; then
            echo -e "${RED}Error : Failed to clear active project${NC}" >&2
            return 1
        fi
        
        echo
        echo "=========================================="
        echo -e "${GREEN}✔ Active project cleared successfully!${NC}"
        echo "=========================================="
        echo
        echo -e "${GREEN}✔ No active project is now set${NC}"
        echo -e "${GREEN}✔ PROJECT_ROOT environment variable removed${NC}"
        
        return 0
    fi
    
    # Validate project name :
    if ! validate_project_name "$project_name"; then
        return 1
    fi
    
    local project_path="$QUALCOMM_ROOT/projects/$project_name"
    
    echo "=========================================="
    echo "Setting active project : $project_name"
    echo "=========================================="
    echo
    
    # Check if project exists :
    if [ ! -d "$project_path" ]; then
        echo -e "${RED}Error : Project does not exist : $project_path${NC}" >&2
        echo "Available projects :"
        local projects_dir="$QUALCOMM_ROOT/projects"
        if [ -d "$projects_dir" ]; then
            local projects=$(ls -1 "$projects_dir" 2>/dev/null | grep -v "^backup$" || echo "  None found")
            echo "$projects" | sed 's/^/  /'
        else
            echo "  No projects directory found"
        fi
        return 1
    fi
    
    # Check if already active :
    if [ "$project_name" = "$current_active" ]; then
        echo -e "${YELLOW}Info : Project '$project_name' is already the active project${NC}"
        echo
        echo "=========================================="
        echo -e "${GREEN}✔ Active project status unchanged${NC}"
        echo "=========================================="
        echo
        echo "Current active project : $project_name"
        echo "Project location : $project_path"
        echo "PROJECT_ROOT : $PROJECT_ROOT"
        echo
        return 0
    fi
    
    # Show transition :
    if [ -n "$current_active" ]; then
        echo "Current active project : $current_active"
        echo "New active project     : $project_name"
    else
        echo "No current active project"
        echo "New active project : $project_name"
    fi
    echo
    
    # Update active project :
    echo "Updating active project..."
    if ! update_active_project "$project_name"; then
        echo -e "${RED}Error : Failed to update active project${NC}" >&2
        return 1
    fi
    
    echo
    echo "=========================================="
    echo -e "${GREEN}✔ Active project set successfully!${NC}"
    echo "=========================================="
    echo
    echo "Active project : $project_name"
    echo "Project location : $project_path"
    echo
    echo -e "${GREEN}✔ Project is now set as active${NC}"
    echo -e "${GREEN}✔ PROJECT_ROOT environment variable exported${NC}"
    
    return 0
}

# RESTORE command implementation :
cmd_restore() {
    local backup_name=""
    local restore_name=""
    local set_active=false
    local keep_backup=false
    
    # Parse restore-specific arguments :
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Backup name is required after $1${NC}" >&2
                    return 1
                fi
                backup_name="$2"
                shift 2
                ;;
            -nn|--new-name)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : New project name is required after $1${NC}" >&2
                    return 1
                fi
                restore_name="$2"
                shift 2
                ;;
            -a|--active)
                set_active=true
                shift
                ;;
            -b)
                keep_backup=true
                shift
                ;;
            *)
                echo -e "${RED}Error : Unknown option for restore command : $1${NC}" >&2
                return 1
                ;;
        esac
    done
    
    # Validate required arguments :
    if [ -z "$backup_name" ]; then
        echo -e "${RED}Error : Backup name is required for restore command${NC}" >&2
        echo "Use : $SCRIPT_NAME restore -n <backup_name>"
        return 1
    fi
    
    # Set restore name to backup name if not specified :
    if [ -z "$restore_name" ]; then
        restore_name="$backup_name"
    fi
    
    # Validate project names :
    if ! validate_project_name "$backup_name"; then
        return 1
    fi
    
    if ! validate_project_name "$restore_name"; then
        return 1
    fi
    
    local backup_path="$QUALCOMM_ROOT/projects/backup/BACKUP_$backup_name"
    local restore_path="$QUALCOMM_ROOT/projects/$restore_name"
    
    echo "=========================================="
    echo "Restoring project : $backup_name"
    if [ "$backup_name" != "$restore_name" ]; then
        echo "Restore as : $restore_name"
    fi
    echo "=========================================="
    echo
    
    # Check if backup exists :
    if [ ! -d "$backup_path" ]; then
        echo -e "${RED}Error : Backup does not exist : $backup_path${NC}" >&2
        echo "Available backups :"
        local backup_dir="$QUALCOMM_ROOT/projects/backup"
        if [ -d "$backup_dir" ]; then
            local backups=$(ls -1 "$backup_dir" 2>/dev/null | grep "^BACKUP_" | sed 's/^BACKUP_//' || echo "  None found")
            echo "$backups" | sed 's/^/  /'
        else
            echo "  No backup directory found"
        fi
        return 1
    fi
    
    # Check if restore target already exists :
    if [ -e "$restore_path" ]; then
        echo -e "${RED}Error : Project with restore name already exists : $restore_path${NC}" >&2
        return 1
    fi
    
    # Restore project :
    echo "Restoring project..."
    echo "From : $backup_path"
    echo "To   : $restore_path"
    
    if ! cp -r "$backup_path" "$restore_path"; then
        echo -e "${RED}Error : Failed to restore project from backup${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}✔ Project restored from backup${NC}"
    
    echo
    
    # Remove backup if not keeping it :
    if [ "$keep_backup" = false ]; then
        echo "Removing backup..."
        if ! rm -rf "$backup_path"; then
            echo -e "${YELLOW}Warning : Failed to remove backup : $backup_path${NC}" >&2
        else
            echo -e "${GREEN}✔ Backup removed${NC}"
        fi
        echo
    fi
    
    # Set as active project if requested :
    if [ "$set_active" = true ]; then
        if ! update_active_project "$restore_name"; then
            echo -e "${YELLOW}Warning : Project restored but failed to update active project${NC}" >&2
            return 1
        fi
    else
        echo "Project restored successfully but not set as active."
        echo "To set as active project, run :"
        echo "$SCRIPT_NAME restore -n $backup_name --active"
        if [ "$backup_name" != "$restore_name" ]; then
            echo "Or : $SCRIPT_NAME create -n $restore_name --active"
        fi
    fi
    
    echo
    echo "=========================================="
    echo -e "${GREEN}✔ Project '$restore_name' restored successfully!${NC}"
    echo "=========================================="
    echo
    echo "Restored location : $restore_path"
    echo "Original backup : $backup_path"
    echo
    
    if [ "$keep_backup" = true ]; then
        echo -e "${GREEN}✔ Backup preserved${NC}"
    else
        echo -e "${GREEN}✔ Backup removed after restore${NC}"
    fi
    
    if [ "$set_active" = true ]; then
        echo -e "${GREEN}✔ Project is now set as active${NC}"
        echo -e "${GREEN}✔ PROJECT_ROOT environment variable exported${NC}"
    fi
    
    return 0
}

# Function to get current active project :
get_active_project() {
    local config_file="$QUALCOMM_ROOT/scripts/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo ""
        return 1
    fi
    
    local active_project=$(jq -r '.names.project // ""' "$config_file" 2>/dev/null)
    echo "$active_project"
}

# Function to update active project in config :
update_active_project() {
    local project_name="$1"
    local config_file="$QUALCOMM_ROOT/scripts/config.json"
    
    # Check if config file exists :
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error : Config file not found : $config_file${NC}" >&2
        return 1
    fi
    
    # Check if jq is available :
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error : jq is required for JSON manipulation but not installed${NC}" >&2
        return 1
    fi
    
    # Update the project name in config.json :
    local temp_file=$(mktemp)
    if ! jq --arg project_name "$project_name" '.names.project = $project_name' "$config_file" > "$temp_file"; then
        echo -e "${RED}Error : Failed to update config.json${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # Replace original file with updated content :
    if ! mv "$temp_file" "$config_file"; then
        echo -e "${RED}Error : Failed to save updated config.json${NC}" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    if [ -n "$project_name" ]; then
        echo -e "${GREEN}✔ Updated config.json : active project set to '$project_name'${NC}"
        
        # Export PROJECT_ROOT environment variable :
        local project_root="$QUALCOMM_ROOT/projects/$project_name"
        export PROJECT_ROOT="$project_root"
        echo -e "${GREEN}✔ Exported PROJECT_ROOT=$PROJECT_ROOT${NC}"
    else
        echo -e "${GREEN}✔ Updated config.json : active project cleared${NC}"
        unset PROJECT_ROOT
        echo -e "${GREEN}✔ Removed PROJECT_ROOT environment variable${NC}"
    fi
    
    return 0
}

# Function to create backup :
create_backup() {
    local project_name="$1"
    local source_path="$QUALCOMM_ROOT/projects/$project_name"
    local backup_dir="$QUALCOMM_ROOT/projects/backup"
    local backup_path="$backup_dir/BACKUP_$project_name"
    
    echo "Creating backup..."
    
    # Check if source project exists :
    if [ ! -d "$source_path" ]; then
        echo -e "${RED}Error : Source project not found : $source_path${NC}" >&2
        return 1
    fi
    
    # Create backup directory if it doesn't exist :
    if [ ! -d "$backup_dir" ]; then
        if ! mkdir -p "$backup_dir"; then
            echo -e "${RED}Error : Failed to create backup directory : $backup_dir${NC}" >&2
            return 1
        fi
    fi
    
    # Check if backup already exists :
    if [ -e "$backup_path" ]; then
        echo -e "${RED}Error : Backup already exists : $backup_path${NC}" >&2
        return 1
    fi
    
    # Create backup :
    if ! cp -r "$source_path" "$backup_path"; then
        echo -e "${RED}Error : Failed to create backup${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✔ Backup created : $backup_path${NC}"
    return 0
}

# Function to create project structure :
create_project_structure() {
    local project_name="$1"
    local project_path="$QUALCOMM_ROOT/projects/$project_name"
    
    echo "Creating project structure..."
    echo "Project path : $project_path"
    
    # Check if project directory already exists :
    if [ -e "$project_path" ]; then
        echo -e "${RED}Error : Project directory already exists : $project_path${NC}" >&2
        return 1
    fi
    
    # Create main project directory :
    if ! mkdir -p "$project_path"; then
        echo -e "${RED}Error : Failed to create project directory : $project_path${NC}" >&2
        return 1
    fi
    
    # Create subdirectories :
    local subdirs=("data" "models" "outputs")
    for subdir in "${subdirs[@]}"; do
        local full_path="$project_path/$subdir"
        if ! mkdir -p "$full_path"; then
            echo -e "${RED}Error : Failed to create directory : $full_path${NC}" >&2
            # Clean up on failure :
            rm -rf "$project_path"
            return 1
        fi
        echo -e "${GREEN}✔${NC} Created : $full_path"
    done
    
    echo -e "${GREEN}✔ Project structure created successfully${NC}"
    return 0
}

# CREATE command implementation :
cmd_create() {
    local project_name=""
    local set_active=false
    
    # Parse create-specific arguments :
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Project name is required after $1${NC}" >&2
                    return 1
                fi
                project_name="$2"
                shift 2
                ;;
            -a|--active)
                set_active=true
                shift
                ;;
            -nn|--new-name)
                echo -e "${RED}Error : --new-name is not valid for create command${NC}" >&2
                return 1
                ;;
            -b)
                echo -e "${RED}Error : -b (backup) is not valid for create command${NC}" >&2
                return 1
                ;;
            *)
                echo -e "${RED}Error : Unknown option for create command : $1${NC}" >&2
                return 1
                ;;
        esac
    done
    
    # Validate required arguments :
    if [ -z "$project_name" ]; then
        echo -e "${RED}Error : Project name is required for create command${NC}" >&2
        echo "Use : $SCRIPT_NAME create -n <project_name>"
        return 1
    fi
    
    # Validate project name :
    if ! validate_project_name "$project_name"; then
        return 1
    fi
    
    echo "=========================================="
    echo "Creating new project : $project_name"
    echo "=========================================="
    echo
    
    # Create project structure :
    if ! create_project_structure "$project_name"; then
        return 1
    fi
    
    echo
    
    # Update active project if requested :
    if [ "$set_active" = true ]; then
        if ! update_active_project "$project_name"; then
            echo -e "${YELLOW}Warning : Project created but failed to update active project${NC}" >&2
            return 1
        fi
    else
        echo "Project created successfully but not set as active."
        echo "To set as active project, run :"
        echo "$SCRIPT_NAME create -n $project_name --active"
    fi
    
    echo
    echo "=========================================="
    echo -e "${GREEN}✔ Project '$project_name' created successfully!${NC}"
    echo "=========================================="
    echo
    echo "Project location : $QUALCOMM_ROOT/projects/$project_name"
    echo "Directory structure :"
    echo "├── data/"
    echo "├── models/"
    echo "└── outputs/"
    echo
    
    if [ "$set_active" = true ]; then
        echo -e "${GREEN}✔ Project is now set as active${NC}"
        echo -e "${GREEN}✔ PROJECT_ROOT environment variable exported${NC}"
    fi
    
    return 0
}

# DELETE command implementation :
cmd_delete() {
    local project_name=""
    local new_active=""
    local create_backup=false
    local set_active=false
    
    # Parse delete-specific arguments :
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Project name is required after $1${NC}" >&2
                    return 1
                fi
                project_name="$2"
                shift 2
                ;;
            -a|--active)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Active project name is required after $1${NC}" >&2
                    return 1
                fi
                new_active="$2"
                set_active=true
                shift 2
                ;;
            -b)
                create_backup=true
                shift
                ;;
            -nn|--new-name)
                echo -e "${RED}Error : --new-name is not valid for delete command${NC}" >&2
                return 1
                ;;
            *)
                echo -e "${RED}Error : Unknown option for delete command : $1${NC}" >&2
                return 1
                ;;
        esac
    done
    
    # Validate required arguments :
    if [ -z "$project_name" ]; then
        echo -e "${RED}Error : Project name is required for delete command${NC}" >&2
        echo "Use : $SCRIPT_NAME delete -n <project_name>"
        return 1
    fi
    
    # Validate project name :
    if ! validate_project_name "$project_name"; then
        return 1
    fi
    
    # Validate new active project name if provided :
    if [ "$set_active" = true ] && ! validate_project_name "$new_active"; then
        return 1
    fi
    
    local project_path="$QUALCOMM_ROOT/projects/$project_name"
    local current_active=$(get_active_project)
    
    echo "=========================================="
    echo "Deleting project : $project_name"
    echo "=========================================="
    echo
    
    # Check if project exists :
    if [ ! -d "$project_path" ]; then
        echo -e "${RED}Error : Project does not exist : $project_path${NC}" >&2
        return 1
    fi
    
    # Check if new active project exists (if specified) :
    if [ "$set_active" = true ]; then
        local new_active_path="$QUALCOMM_ROOT/projects/$new_active"
        if [ ! -d "$new_active_path" ]; then
            echo -e "${RED}Error : New active project does not exist : $new_active_path${NC}" >&2
            return 1
        fi
    fi
    
    # Create backup if requested :
    if [ "$create_backup" = true ]; then
        if ! create_backup "$project_name"; then
            return 1
        fi
        echo
    fi
    
    # Delete project directory :
    echo "Deleting project directory..."
    if ! rm -rf "$project_path"; then
        echo -e "${RED}Error : Failed to delete project directory : $project_path${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}✔ Project directory deleted${NC}"
    
    echo
    
    # Handle active project updates :
    if [ "$project_name" = "$current_active" ]; then
        # Deleting the currently active project :
        if [ "$set_active" = true ]; then
            # Set new active project :
            if ! update_active_project "$new_active"; then
                echo -e "${YELLOW}Warning : Project deleted but failed to update active project${NC}" >&2
                return 1
            fi
        else
            # Clear active project :
            echo -e "${YELLOW}Warning : Deleted project was the active project${NC}"
            if ! update_active_project ""; then
                echo -e "${YELLOW}Warning : Failed to clear active project in config${NC}" >&2
                return 1
            fi
        fi
    else
        # Deleting a non-active project :
        if [ "$set_active" = true ]; then
            # Warning about updating active project when deleted project wasn't active :
            echo -e "${YELLOW}Warning : Setting new active project, but deleted project was not the active one${NC}"
            if ! update_active_project "$new_active"; then
                echo -e "${YELLOW}Warning : Project deleted but failed to update active project${NC}" >&2
                return 1
            fi
        fi
    fi
    
    echo
    echo "=========================================="
    echo -e "${GREEN}✔ Project '$project_name' deleted successfully!${NC}"
    echo "=========================================="
    echo
    
    if [ "$create_backup" = true ]; then
        echo -e "${GREEN}✔ Backup created before deletion${NC}"
    fi
    
    if [ "$set_active" = true ]; then
        echo -e "${GREEN}✔ Active project updated to '$new_active'${NC}"
    elif [ "$project_name" = "$current_active" ]; then
        echo -e "${YELLOW}⚠ Active project cleared (deleted project was active)${NC}"
    fi
    
    return 0
}

# RENAME command implementation :
cmd_rename() {
    local old_name=""
    local new_name=""
    local set_active=false
    local create_backup=false
    
    # Parse rename-specific arguments :
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : Project name is required after $1${NC}" >&2
                    return 1
                fi
                old_name="$2"
                shift 2
                ;;
            -nn|--new-name)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error : New project name is required after $1${NC}" >&2
                    return 1
                fi
                new_name="$2"
                shift 2
                ;;
            -a|--active)
                set_active=true
                shift
                ;;
            -b)
                create_backup=true
                shift
                ;;
            *)
                echo -e "${RED}Error : Unknown option for rename command : $1${NC}" >&2
                return 1
                ;;
        esac
    done
    
    # Validate required arguments :
    if [ -z "$old_name" ]; then
        echo -e "${RED}Error : Current project name is required for rename command${NC}" >&2
        echo "Use : $SCRIPT_NAME rename -n <old_name> -nn <new_name>"
        return 1
    fi
    
    if [ -z "$new_name" ]; then
        echo -e "${RED}Error : New project name is required for rename command${NC}" >&2
        echo "Use : $SCRIPT_NAME rename -n <old_name> -nn <new_name>"
        return 1
    fi
    
    # Validate project names :
    if ! validate_project_name "$old_name"; then
        return 1
    fi
    
    if ! validate_project_name "$new_name"; then
        return 1
    fi
    
    local old_path="$QUALCOMM_ROOT/projects/$old_name"
    local new_path="$QUALCOMM_ROOT/projects/$new_name"
    local current_active=$(get_active_project)
    
    echo "=========================================="
    echo "Renaming project : $old_name → $new_name"
    echo "=========================================="
    echo
    
    # Check if old project exists :
    if [ ! -d "$old_path" ]; then
        echo -e "${RED}Error : Project does not exist : $old_path${NC}" >&2
        return 1
    fi
    
    # Check if new project name already exists :
    if [ -e "$new_path" ]; then
        echo -e "${RED}Error : Project with new name already exists : $new_path${NC}" >&2
        return 1
    fi
    
    # Create backup if requested :
    if [ "$create_backup" = true ]; then
        if ! create_backup "$old_name"; then
            return 1
        fi
        echo
    fi
    
    # Rename project directory :
    echo "Renaming project directory..."
    echo "From : $old_path"
    echo "To   : $new_path"
    
    if ! mv "$old_path" "$new_path"; then
        echo -e "${RED}Error : Failed to rename project directory${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}✔ Project directory renamed${NC}"
    
    echo
    
    # Handle active project updates :
    if [ "$old_name" = "$current_active" ]; then
        # Renaming the currently active project :
        if [ "$set_active" = true ]; then
            # Update active project to new name :
            if ! update_active_project "$new_name"; then
                echo -e "${YELLOW}Warning : Project renamed but failed to update active project${NC}" >&2
                return 1
            fi
        else
            # Clear active project :
            echo -e "${YELLOW}Warning : Renamed project was the active project${NC}"
            if ! update_active_project ""; then
                echo -e "${YELLOW}Warning : Failed to clear active project in config${NC}" >&2
                return 1
            fi
        fi
    else
        # Renaming a non-active project :
        if [ "$set_active" = true ]; then
            # Warning about updating active project when renamed project wasn't active :
            echo -e "${YELLOW}Warning : Setting new name as active, but renamed project was not the active one${NC}"
            if ! update_active_project "$new_name"; then
                echo -e "${YELLOW}Warning : Project renamed but failed to update active project${NC}" >&2
                return 1
            fi
        fi
    fi
    
    echo
    echo "=========================================="
    echo -e "${GREEN}✔ Project renamed successfully!${NC}"
    echo "=========================================="
    echo
    echo "Old location : $old_path"
    echo "New location : $new_path"
    echo
    
    if [ "$create_backup" = true ]; then
        echo -e "${GREEN}✔ Backup created before rename${NC}"
    fi
    
    if [ "$set_active" = true ]; then
        echo -e "${GREEN}✔ Active project updated to '$new_name'${NC}"
    elif [ "$old_name" = "$current_active" ]; then
        echo -e "${YELLOW}⚠ Active project cleared (renamed project was active)${NC}"
    fi
    
    return 0
}

# Main function :
main() {
    # Check basic requirements first :
    if [ -z "$QUALCOMM_ROOT" ]; then
        echo
        echo -e "${RED}Error : QUALCOMM_ROOT environment variable is not set${NC}" >&2
        echo
        
    fi
    
    if [ ! -d "$QUALCOMM_ROOT" ]; then
        echo
        echo -e "${RED}Error : QUALCOMM_ROOT directory does not exist : $QUALCOMM_ROOT${NC}" >&2
        echo
        
    fi
    
    # Create projects directory if it doesn't exist :
    local projects_dir="$QUALCOMM_ROOT/projects"
    if [ ! -d "$projects_dir" ]; then
        echo "Projects directory does not exist, creating : $projects_dir"
        if ! mkdir -p "$projects_dir"; then
            echo
            echo -e "${RED}Error : Failed to create projects directory : $projects_dir${NC}" >&2
            echo
            
        fi
    fi
    
    # Parse command :
    if [ $# -eq 0 ]; then
        echo
        echo -e "${RED}Error : No command specified${NC}" >&2
        echo "Use : $SCRIPT_NAME <command> [options]"
        echo "Use : $SCRIPT_NAME --help for more information"
        echo
        
    fi
    
    local command="$1"
    shift
    
    # Handle global options :
    case "$command" in
        -h|--help)
            show_help
            exit 0
            ;;
        create|delete|rename|restore|set-active)
            # Valid commands, continue processing :
            ;;
        *)
            echo
            echo -e "${RED}Error : Unknown command : $command${NC}" >&2
            echo "Valid commands : create, delete, rename, restore, set-active"
            echo "Use : $SCRIPT_NAME --help for more information"
            echo
            
            ;;
    esac
    
    # Execute command :
    echo
    case "$command" in
        create)
            if ! cmd_create "$@"; then
                echo
                
            fi
            ;;
        delete)
            if ! cmd_delete "$@"; then
                echo
                
            fi
            ;;
        rename)
            if ! cmd_rename "$@"; then
                echo
                
            fi
            ;;
        restore)
            if ! cmd_restore "$@"; then
                echo
                
            fi
            ;;
        set-active)
            if ! cmd_set_active "$@"; then
                echo
                
            fi
            ;;
    esac
    
    echo
}

# Run main function with all arguments :
main "$@"

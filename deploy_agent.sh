#!/bin/bash
# deploy_agent.sh
# Deploys, runs and archives the logs of the attendance tracker.
# Run it from the repo root (the folder that contains templates/).

# ================================================================
# Shared settings and state
# ================================================================
TEMPLATES="templates"          # where the three source files live
PREFIX="attendance_tracker_"   # every project folder starts with this
IN_PROGRESS=""                 # folder being built right now (the trap reads it)
TARGET=""                      # folder chosen during deployment

# ================================================================
# Small helpers
# ================================================================

# succeeds only if the argument is a whole number
is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# project name -> project folder name
folder_for() {
    echo "${PREFIX}$1"
}

# stop catching Ctrl+C / Ctrl+Z and forget the half-built folder
disarm_trap() {
    IN_PROGRESS=""
    trap - SIGINT SIGTSTP
}

# undo a failed build step: print the reason, delete the folder, release the trap
# usage: fail_build "reason" "folder"
fail_build() {
    echo "Error: $1"
    rm -rf "$2"
    disarm_trap
}

# runs when the user presses Ctrl+C or Ctrl+Z during deployment
on_interrupt() {
    echo ""
    echo "Deployment was interrupted!"
    if [ -n "$IN_PROGRESS" ] && [ -d "$IN_PROGRESS" ]; then
        echo "Zipping the incomplete project..."
        if zip -r "${IN_PROGRESS}_archive.zip" "$IN_PROGRESS" > /dev/null; then
            rm -rf "$IN_PROGRESS"
            echo "Saved ${IN_PROGRESS}_archive.zip and deleted $IN_PROGRESS"
        else
            echo "zip failed, so I left $IN_PROGRESS alone"
        fi
    else
        echo "Nothing was created yet."
    fi
    echo "Closing the session."
    exit 1
}

# ================================================================
# Feature 1: deploy  (one small function per step)
# ================================================================

# step 1: make sure the tools and the templates folder are there
preflight_checks() {
    local tool
    for tool in python3 zip; do
        if ! command -v "$tool" > /dev/null; then
            echo "Error: $tool is not installed."
            return 1
        fi
    done
    python3 --version

    if [ ! -d "$TEMPLATES" ]; then
        echo "Error: templates/ folder not found. Run this from the root, repo folder."
        return 1
    fi
}

# step 2: ask for a name, handle an existing folder, create the structure
create_structure() {
    local name answer
    read -p "Enter a name for the project: " name
    if [ -z "$name" ]; then
        echo "Error: the name cannot be empty."
        return 1
    fi
    TARGET=$(folder_for "$name")

    # catch Ctrl+C and Ctrl+Z from here on
    trap on_interrupt SIGINT SIGTSTP

    if [ -d "$TARGET" ]; then
        read -p "$TARGET already exists. Overwrite it? (y/n): " answer
        if [ "$answer" != "y" ]; then
            echo "Aborted. Nothing was changed."
            disarm_trap
            return 1
        fi
        if ! rm -rf "$TARGET"; then
            echo "Error: could not delete $TARGET"
            disarm_trap
            return 1
        fi
    fi

    if ! mkdir -p "$TARGET/Helpers" "$TARGET/reports"; then
        fail_build "could not create $TARGET (permission denied?)" "$TARGET"
        return 1
    fi
    IN_PROGRESS="$TARGET"
    echo "Created $TARGET with Helpers/ and reports/"
}

# step 3a: copy the app and its config out of templates/
copy_sources() {
    local dir=$1
    if ! cp "$TEMPLATES/attendance_checker.py" "$dir/"; then
        fail_build "could not copy attendance_checker.py" "$dir"
        return 1
    fi
    if ! cp "$TEMPLATES/config.json" "$dir/Helpers/"; then
        fail_build "could not copy config.json" "$dir"
        return 1
    fi
}

# step 3b: build the student roster (copy it, or generate a new one)
build_roster() {
    local dir=$1
    local choice count rows i student suffix email
    local -a names=(Alice Bob Charlie Diana Edward Fiona George Hannah Ian Julia)

    echo "How do you want to build the roster?"
    echo "A) copy from templates/assets.csv"
    echo "B) generate a fresh roster"
    read -p "Choose A or B: " choice
    while [ "$choice" != "A" ] && [ "$choice" != "B" ]; do
        read -p "Please type A or B: " choice
    done

    read -p "How many students? " count
    while ! is_number "$count" || [ "$count" -lt 1 ]; do
        read -p "Please enter a number greater than 0: " count
    done

    if [ "$choice" = "A" ]; then
        # header line + the number of students asked for
        head -n $((count + 1)) "$TEMPLATES/assets.csv" > "$dir/Helpers/assets.csv"
        rows=$(( $(grep -c "" "$dir/Helpers/assets.csv") - 1 ))
        echo "Copied $rows students from the template (4 sessions already recorded)."
        echo "total_sessions stays at 5."
    else
        echo "Email,Names,Attendance Count,Absence Count" > "$dir/Helpers/assets.csv"
        for ((i = 0; i < count; i++)); do
            suffix=""
            if [ "$i" -ge 10 ]; then
                suffix=$((i / 10 + 1))
            fi
            student="${names[$((i % 10))]}${suffix}"
            email="${student,,}@example.com"
            echo "$email,$student,0,0" >> "$dir/Helpers/assets.csv"
        done
        # a fresh roster means this is session number 1
        sed -i 's/"total_sessions": 5/"total_sessions": 1/' "$dir/Helpers/config.json"
        echo "Generated $count students. total_sessions set to 1."
    fi
}

# step 4: executable app, private config
apply_permissions() {
    local dir=$1
    chmod +x "$dir/attendance_checker.py"
    chmod 600 "$dir/Helpers/config.json"
    echo "Permissions set:"
    ls -l "$dir/attendance_checker.py" "$dir/Helpers/config.json"
}

# step 5: optionally change the warning / failure thresholds in config.json
configure_thresholds() {
    local dir=$1
    local change level value
    read -p "Do you want to change the alert thresholds? (y/n): " change
    if [ "$change" != "y" ]; then
        return 0
    fi

    for level in warning failure; do
        read -p "New $level threshold (0-100): " value
        while ! is_number "$value" || [ "$value" -gt 100 ]; do
            read -p "Enter a number between 0 and 100: " value
        done
        sed -i "s/\(\"$level\": \)[0-9]*/\1$value/" "$dir/Helpers/config.json"
    done
    echo "Updated config.json:"
    grep -E '"warning"|"failure"' "$dir/Helpers/config.json"
}

# glue: run the steps in order, stop quietly if one of the early ones fails
deploy() {
    local dir

    preflight_checks || return
    create_structure || return
    dir="$TARGET"
    copy_sources "$dir" || return
    build_roster "$dir"
    apply_permissions "$dir"
    configure_thresholds "$dir"

    # deployment is done, so stop catching the signals
    disarm_trap

    # step 6: verify by running the app (subshell, so we never change directory)
    echo "Deployment finished. Running the app to verify..."
    ( cd "$dir" && python3 attendance_checker.py )
}

# ================================================================
# Feature 2: run
# ================================================================
run_app() {
    local name dir
    read -p "Project name: " name
    dir=$(folder_for "$name")
    if [ ! -d "$dir" ]; then
        echo "Error: $dir does not exist. Deploy it first."
        return
    fi
    ( cd "$dir" && python3 attendance_checker.py )
}

# ================================================================
# Feature 3: archive the logs
# ================================================================
archive_logs() {
    local name dir stamp log log_file target_dir
    read -p "Project name: " name
    dir=$(folder_for "$name")
    if [ ! -d "$dir" ]; then
        echo "Error: $dir does not exist."
        return
    fi

    stamp=$(date +%Y%m%d_%H%M%S)

    for log in attendance absent; do
        log_file="$dir/reports/$log.log"
        if [ ! -f "$log_file" ]; then
            echo "$log.log does not exist, nothing to archive."
            continue
        fi
        target_dir="$dir/archives/$log"
        mkdir -p "$target_dir"
        mv "$log_file" "$target_dir/${log}_$stamp.log"
        echo "Archived $log.log -> $target_dir/${log}_$stamp.log"
    done
}

# ================================================================
# Main menu
# ================================================================
main_menu() {
    local option
    while true; do
        echo ""
        echo "===== Deploy Agent ====="
        echo "1) Deploy the application"
        echo "2) Run the application"
        echo "3) Archive the logs"
        echo "4) Exit"
        read -p "Choose an option: " option
        case "$option" in
            1) deploy ;;
            2) run_app ;;
            3) archive_logs ;;
            4) echo "SEE YOU, G!"; exit 0 ;;
            *) echo "Invalid option, try again." ;;
        esac
    done
}

main_menu

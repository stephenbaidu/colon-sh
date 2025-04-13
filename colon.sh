#!/bin/bash

# If running in zsh, switch to bash emulation.
if [ -n "$ZSH_VERSION" ]; then
    emulate bash -c 'true'
fi

scriptdir=$(dirname -- "$(realpath -- "$0")")

# Aliases
alias ::=":_:"
alias :init=":_init"
alias :main="git checkout main"
alias :master="git checkout master"
alias :gs="git status"
alias :ll="git pull"
alias :gaa="git add ."
alias :gp="git push"
alias :gpf="git push --force"
alias :gh="git log --oneline --graph --decorate"
alias :gb=":_gb"
alias :nb=":_nb"
alias :gc=":_gc"
alias :gca=":_gca"
alias :prs=":_prs"
alias :pd=":_pd"
alias :po=":_po"
alias :pa=":_pa"

json_file_path=$(eval echo ~/colon.json)

if [[ -f $json_file_path ]]; then
    COLON_JSON_DATA=$(cat "$json_file_path")
    COLON_RETURN_DATA=""
    export COLON_JSON_DATA
    echo "colon-sh: loaded succesfully"
else
    echo "colon-sh: failed to load file at $json_file_path"
    echo "colon-sh: please run :init to create colon.json"
    echo "colon-sh: or edit the file to add your projects and actions."
    return 1
fi

:_:() {
    echo "Welcome to colon.sh! Script: $scriptdir, JSON: $json_file_path"
    echo "Usage:"
    echo "  :init: Initialize colon.json file if it doesn't exist"
    echo "  :pd: Change directory to a project"
    echo "  :po: Open project in configured IDE"
    echo "  :pa: Run actions for the project"
    echo "  :main: Switch to main branch"
    echo "  :master: Switch to master branch"
    echo "  :gs: git status"
    echo "  :ll: git pull"
    echo "  :gaa: git add ."
    echo "  :gp: git push"
    echo "  :gpf: git push --force"
    echo "  :gh: git log --oneline --graph --decorate"
    echo "  :gb: Select a git branch"
    echo "  :nb: Create a new branch"
    echo "  :gc: git commit"
    echo "  :gca: git commit --amend"
    echo "  :prs: Open pull requests in the browser"
}

:_clear_lines() {
    local lines=$1
    # For each line, move the cursor up one line and clear that line.
    for ((i = 0; i < lines; i++)); do
        # "\033[1A" moves the cursor up one line.
        # "\033[2K" clears the entire line.
        echo -ne "\033[1A\033[2K"
    done
}

:_get_cursor_row() {
    # Save terminal settings
    old_stty=$(stty -g)
    # Switch to raw mode to read the response
    stty raw -echo
    # Ask for the cursor position
    printf "\033[6n" >/dev/tty
    # Read the response: ESC [ rows ; cols R
    IFS=';' read -r -d R row col
    # Restore terminal settings
    stty "$old_stty"
    # Remove the ESC [ from the row value
    row=$(echo "$row" | tr -d '\033[')
    echo "$row"
}

:_init() {
    # Check if the JSON file exists
    if [[ -f $json_file_path ]]; then
        echo "colon.json already exists at $json_file_path"
        return 1
    fi

    # Create the JSON file with default content
    cat <<EOF >"$json_file_path"
{
    "version": "0.0.1",
    "open_cmd": "code .",
    "dir_projects": [
        {
            "path": "~/MyProjects",
            "exclude": [
                "bin",
                "notes"
            ]
        }
    ],
    "git_repos": {
        "git@github.com:octocat/Hello-World.git": {
            "name": "Hello-World",
            "actions": [
                {
                    "name": "PRs",
                    "cmd": "xdg-open https://github.com/octocat/Hello-World/pulls"
                }
            ]
        }
    }
}
EOF
    echo "colon.json created at $json_file_path"
    echo "Please edit the file to add your projects and actions."
    return 0
}

:_project_dir() {
    COLON_RETURN_DATA=null
    first_row=$(:_get_cursor_row)
    dirs=()
    counter=0

    # Process each entry in dir_projects as a JSON object.
    while IFS= read -r dir_project; do
        # Extract project path and expand it (handles ~ and globs)
        project_path=$(echo "$dir_project" | jq -r '.path')
        expanded_path=$(eval echo "$project_path")
        echo "$project_path:"

        # If the project has an exclude list, then process subdirectories.
        if echo "$dir_project" | jq -e '(.exclude // []) | length > 0' >/dev/null; then
            # Iterate over each subdirectory under the expanded path.
            for sub in "$expanded_path"/*/; do
                # Ensure it's a directory.
                [ -d "$sub" ] || continue
                # Get basename
                dir_name=$(basename "$sub")
                # Use jq to check if exclude array contains this directory name.
                if echo "$dir_project" | jq -e --arg dn "$dir_name" '(.exclude // []) | index($dn)' >/dev/null; then
                    # Skip this directory if it's in the exclude list.
                    continue
                fi
                dirs+=("$sub")
                ((counter++))
                echo "  $counter. $(basename "$sub")"
            done
        else
            # No exclusion list; simply add the expanded path.
            dirs+=("$expanded_path")
            ((counter++))
            echo "  $counter. $(basename "$expanded_path")"
        fi
    done < <(echo "$COLON_JSON_DATA" | jq -c -r '.dir_projects[]')

    ((counter++))
    echo "$counter) Cancel"

    while true; do
        echo -n "Please enter your choice: "
        read -r REPLY
        if [[ $REPLY -ge 1 && $REPLY -le $counter ]]; then
            if [[ $REPLY -eq $counter ]]; then
                last_row=$(:_get_cursor_row)
                echo "last_row: $last_row"
                :_clear_lines "($last_row-$first_row+1)"
                echo "Cancelled."
                return -1
            else
                last_row=$(:_get_cursor_row)
                echo "last_row: $last_row"
                :_clear_lines "($last_row-$first_row+1)"
                COLON_RETURN_DATA="${dirs[$REPLY]}"
                echo "You selected: $(basename ${dirs[$((REPLY))]})"
                return 0
            fi
        else
            echo "Invalid option. Try another one."
        fi
    done
}

:_simple_select() {
    first_row=$(:_get_cursor_row)
    local prompt="$1"
    shift
    local options=("$@")

    echo "$prompt"

    local i=1
    for option in "${options[@]}"; do
        echo "$i) $option"
        ((i++))
    done
    echo "$i) Cancel"

    while true; do
        echo -n "Please enter your choice: "
        read -r REPLY
        if [[ $REPLY -ge 1 && $REPLY -le $i ]]; then
            if [[ $REPLY -eq $i ]]; then
                last_row=$(:_get_cursor_row)
                echo "last_row: $last_row"
                :_clear_lines "($last_row-$first_row+1)"
                echo "Cancelled."
                return -1
            else
                last_row=$(:_get_cursor_row)
                echo "last_row: $last_row"
                :_clear_lines "($last_row-$first_row+1)"
                echo "You selected: ${options[$((REPLY))]}"
                return $((REPLY))
            fi
        else
            echo "Invalid option. Try another one."
        fi
    done
}

:_pd() {
    :_project_dir

    if [ $? -ne 0 ]; then
        echo "Failed to get project directory."
        return 1
    fi

    cd "$COLON_RETURN_DATA" || exit
    echo "Changed directory to $COLON_RETURN_DATA"
}

:_po() {
    :_project_dir

    if [ $? -ne 0 ]; then
        echo "Failed to get project directory."
        return 1
    fi

    (
        open_cmd=$(jq -r '.open_cmd' <<<"$COLON_JSON_DATA")
        cd "$COLON_RETURN_DATA" || exit

        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            if [ -z "$open_cmd" ] || [ "$open_cmd" = "null" ]; then
                echo "No open command found for this repository."
                return
            fi

            eval "$open_cmd"
            return
        fi

        git_url=$(git remote get-url origin)
        repo_open_cmd=$(jq -r --arg url "$git_url" '.git_repos[$url].open_cmd' <<<"$COLON_JSON_DATA")

        if [ "$repo_open_cmd" != "null" ]; then
            open_cmd="$repo_open_cmd"
        fi

        if [ -z "$open_cmd" ] || [ "$open_cmd" = "null" ]; then
            echo "No open command found for this repository."
            return
        fi

        eval "$open_cmd"
        echo "Opening project at: $COLON_RETURN_DATA with command: $open_cmd"
    )
}

:_pa() {
    :_project_dir

    if [ $? -ne 0 ]; then
        echo "Failed to get project directory."
        return 1
    fi

    (
        cd "$COLON_RETURN_DATA" || exit

        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "This is not a git repository."
            return
        fi

        git_url=$(git remote get-url origin)
        repo_actions=$(jq -r --arg url "$git_url" '.git_repos[$url].actions' <<<"$COLON_JSON_DATA")

        if [ "$repo_actions" = "null" ]; then
            echo "No actions found for this repository."
            return
        fi

        action_names=()

        echo $repo_actions | jq -c '.[]' | while IFS= read -r action; do
            action_name=$(echo "$action" | jq -r '.name')
            action_names+=("$action_name")
        done

        :_simple_select "Select an action:" "${action_names[@]}"

        local selected_index=$?
        if [[ $selected_index -le 0 ]]; then
            echo "No action selected."
            return
        fi

        action_dir=$(echo "$repo_actions" | jq -r ".[$selected_index-1].dir")

        if [[ -n "$action_dir" && "$action_dir" != "null" && "$action_dir" != "." ]]; then
            cd "$action_dir" || exit
        fi

        action_cmd=$(echo "$repo_actions" | jq -r ".[$selected_index-1].cmd")
        echo "Executing command: ${action_cmd} in $(pwd)"
        eval "$action_cmd"
    )
}

:_gb() {
    echo -e "Fetching git branches..."

    local branches=()
    while IFS= read -r line; do
        branches+=("$line")
    done < <(git branch --format="%(refname:short)")

    :_simple_select "Select a branch:" "${branches[@]}"
    
    local selected_index=$?
    if [[ $selected_index -le 0 ]]; then
        echo "No branch selected."
        return
    fi

    local selected_branch="${branches[$((selected_index))]}"

    echo "Switching to branch: $selected_branch"
    git checkout "$selected_branch"
}

:_nb() {
    if [ -z "$1" ]; then
        echo "Usage: :nb <branch-name>"
    else
        local username=$(whoami)
        git checkout -b "dev/${username}/$1"
    fi
}

:_gc() {
    if [ -z "$1" ]; then
        echo "Usage: :gc <commit-message>"
    else
        git commit -m "$*"
    fi
}

:_gca() {
    if [ -z "$1" ]; then
        echo "Usage: :gca <commit-message>":
    else
        git commit -m "$*" --amend
    fi
}

:_prs() {
    # Check if in a git repository
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Get the URL of the remote repository
        origi_url=$(git config --get remote.origin.url)
        
        # Convert SSH URL to HTTP(s) URL
        pulls_url=$(echo "$origi_url" | sed -E 's/^git@([^:]+):/https:\/\/\1\//; s/\.git$/\/pulls/')

        echo "Fetching pull requests from: $pulls_url"
        
        # Open the GitHub Pull Requests page
        echo "Opening: $pulls_url"
        xdg-open "$pulls_url" >/dev/null 2>&1 || open "$pulls_url"
    else
        echo "This is not a git repository."
    fi
}

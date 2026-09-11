#!/bin/bash

# Check for whiptail
if ! command -v whiptail >/dev/null 2>&1; then
    echo "whiptail is not installed. Installing..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y whiptail
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y newt
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm libnewt
    else
        echo "Could not install whiptail. Please install it manually."
        echo "Falling back to command-line interface."
        show_usage
        exit 1
    fi
fi

# =====================
# Server Configuration
# =====================
# Server configuration is stored in .valheim.env
# To configure your server, either:
# 1. Run ./server.sh and select "Server Settings" from the menu
# 2. Run ./server.sh setup
# Do NOT edit these values directly in this file!

# Advanced settings - change only if you know what you're doing
CONTAINER_NAME="valheim-devserver"
IMAGE_NAME="valheim-devserver"
VALHEIM_DATA="./valheim-devdata"
BACKUP_DIR="./valheim-devbackups"
MAX_BACKUPS=24                 # Keep last 24 backups
CACHE_VOLUME="valheim-devcache"   # Docker volume for caching

# Google Drive backup configuration is stored in .valheim.env
# To configure Google Drive backup:
# 1. Run ./server.sh and select "Backup Management" -> "Configure Google Drive Sync"
# 2. Run ./server.sh gdrive-sync-setup

# Load config from .valheim.env if it exists
if [ -f .valheim.env ]; then
    source .valheim.env
fi

# All function definitions above this line

# Function to handle sudo with password prompt
sudo_handler() {
    local command="$1"
    local password
    
    # Check if we already have sudo privileges
    if sudo -n true 2>/dev/null; then
        eval "sudo $command"
        return $?
    fi
    
    # Ask for password
    password=$(whiptail --title "Sudo Required" --passwordbox "\nThis operation requires sudo privileges.\nPlease enter your password:" 12 78 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Execute command with password
    echo "$password" | sudo -S eval "$command" 2>/dev/null
    local result=$?
    
    # Clear password from memory
    password=""
    unset password
    
    return $result
}

# Function to set up rclone/Google Drive backup
backup_storage_setup() {
    if ! command -v rclone &>/dev/null; then
        if (whiptail --title "rclone Installation" --yesno "rclone is not installed. Would you like to install it now?" 8 78); then
            if command -v pacman &>/dev/null; then
                {
                    echo "10"; echo "XXX"; echo "Installing rclone..."; echo "XXX"
                    sudo_handler "pacman -S --noconfirm rclone"
                    echo "100"; echo "XXX"; echo "Installation complete!"; echo "XXX"
                } | whiptail --title "Installing rclone" --gauge "Please wait..." 8 78 0
            else
                whiptail --title "Error" --msgbox "Automatic install not supported on this system.\nPlease install rclone manually (see https://rclone.org/install/)." 10 78
                return 1
            fi
        else
            return 1
        fi
    fi

    # Get remote name
    local default_remote=${RCLONE_REMOTE:-VALHEIM-SDDS}
    local remote=$(whiptail --title "rclone Configuration" --inputbox "Enter the rclone remote name to use for Google Drive:" 8 78 "$default_remote" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return 1; fi

    # Check if remote exists and offer to reconfigure
    if rclone listremotes | grep -q "^$remote:"; then
        if (whiptail --title "Existing Remote" --yesno "Remote '$remote' already exists. Would you like to reconfigure it?" 8 78); then
            {
                echo "25"; echo "XXX"; echo "Deleting existing remote..."; echo "XXX"
                rclone config delete "$remote" --non-interactive
                echo "100"; echo "XXX"; echo "Remote deleted!"; echo "XXX"
            } | whiptail --title "Configuring rclone" --gauge "Please wait..." 8 78 0
        else
            # If not reconfiguring, just get the backup path
            local default_path=${RCLONE_PATH:-valheim-backups}
            local path=$(whiptail --title "Backup Location" --inputbox "Enter the folder path in your Google Drive for backups:" 8 78 "$default_path" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then return 1; fi
            RCLONE_REMOTE="$remote"
            RCLONE_PATH="$path"
            return 0
        fi
    fi

    # Automate rclone config create (type=drive, scope=drive.file)
    {
        echo "0"; echo "XXX"; echo "Creating rclone remote..."; echo "XXX"
        rclone config create "$remote" drive scope=drive.file --non-interactive
        echo "100"; echo "XXX"; echo "Remote created!"; echo "XXX"
    } | whiptail --title "Configuring rclone" --gauge "Please wait..." 8 78 0

    # Prompt user to do OAuth via rclone config reconnect
    whiptail --title "Google Drive Authentication" --msgbox "The next step will open a prompt in your terminal.\n\nYou will see a URL to copy and open in your browser.\n\nAfter authenticating, paste the code back into the terminal.\n\nPress OK to continue." 14 78
    rclone config reconnect "$remote:"

    # After rclone config, continue in whiptail
    local default_path=${RCLONE_PATH:-valheim-backups}
    local path=$(whiptail --title "Backup Location" --inputbox "Enter the folder path in your Google Drive for backups:" 8 78 "$default_path" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return 1; fi

    # Save configuration
    RCLONE_REMOTE="$remote"
    RCLONE_PATH="$path"

    # Update .valheim.env
    {
        grep -v '^RCLONE_REMOTE=' .valheim.env 2>/dev/null | grep -v '^RCLONE_PATH=' > .valheim.env.tmp || true
        mv .valheim.env.tmp .valheim.env 2>/dev/null || true
        echo "RCLONE_REMOTE=$RCLONE_REMOTE" >> .valheim.env
        echo "RCLONE_PATH=$RCLONE_PATH" >> .valheim.env
    }

    whiptail --title "Success" --msgbox "Google Drive backup configuration saved!\n\nRemote: $RCLONE_REMOTE\nPath: $RCLONE_PATH" 10 78

    # Re-source .valheim.env
    if [ -f .valheim.env ]; then
        source .valheim.env
    fi
}

# Function to set up server configuration
setup_server_config() {
    # Server Name
    local server_name=$(whiptail --title "Server Configuration" --inputbox "Enter Server Name:" 8 78 "${SERVER_NAME}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return 1; fi
    SERVER_NAME="$server_name"

    # World Name
    local world_name=$(whiptail --title "Server Configuration" --inputbox "Enter World Name:" 8 78 "${WORLD_NAME}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return 1; fi
    WORLD_NAME="$world_name"

    # Server Password
    while true; do
        local server_pass=$(whiptail --title "Server Configuration" --passwordbox "Enter Server Password (min 5 chars):" 8 78 "${SERVER_PASS}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then return 1; fi
        if [ ${#server_pass} -ge 5 ]; then
            SERVER_PASS="$server_pass"
            break
        else
            whiptail --title "Error" --msgbox "Password must be at least 5 characters long." 8 78
        fi
    done

    # Server Public Setting
    if (whiptail --title "Server Configuration" --yesno "Make server public?" 8 78); then
        SERVER_PUBLIC=1
    else
        SERVER_PUBLIC=0
    fi

    # Crossplay Setting (opens the server to PlayStation/Switch/Xbox players via PlayFab)
    if (whiptail --title "Server Configuration" --yesno "Enable crossplay?\n(Allows PlayStation, Switch, and Xbox players to join in addition to Steam)" 10 78 --defaultno); then
        SERVER_CROSSPLAY=1
    else
        SERVER_CROSSPLAY=0
    fi

    # Backup Settings
    local default_backup=${BACKUP_DIR#./}
    local backup_dir=$(whiptail --title "Backup Configuration" --inputbox "Enter local backup folder name:" 8 78 "$default_backup" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return 1; fi
    BACKUP_DIR="./$backup_dir"
    mkdir -p "$BACKUP_DIR"

    local default_max_bak=${MAX_BACKUPS:-24}
    local max_backups=$(whiptail --title "Backup Configuration" --inputbox "How many backups to keep?" 8 78 "$default_max_bak" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return 1; fi
    MAX_BACKUPS="$max_backups"

    local default_interval=${BACKUP_INTERVAL_HOURS:-1}
    local backup_interval=$(whiptail --title "Backup Configuration" --inputbox "Hours between automatic backups:" 8 78 "$default_interval" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return 1; fi
    BACKUP_INTERVAL_HOURS="$backup_interval"

    # Save configuration to .valheim.env
    {
        echo "SERVER_NAME=$SERVER_NAME"
        echo "WORLD_NAME=$WORLD_NAME"
        echo "SERVER_PASS=$SERVER_PASS"
        echo "SERVER_PUBLIC=$SERVER_PUBLIC"
        echo "SERVER_CROSSPLAY=$SERVER_CROSSPLAY"
        echo "BACKUP_DIR=$BACKUP_DIR"
        echo "MAX_BACKUPS=$MAX_BACKUPS"
        echo "BACKUP_INTERVAL_HOURS=$BACKUP_INTERVAL_HOURS"
    } > .valheim.env

    # Ask about Google Drive backup
    if (whiptail --title "Google Drive Setup" --yesno "Would you like to set up Google Drive backup now?\n(This can be done later using the backup menu)" 10 78); then
        backup_storage_setup
    fi

    # Build Docker image
    {
        echo "0"; echo "XXX"; echo "Building Docker image..."; echo "XXX"
        docker build -t ${IMAGE_NAME} . >/dev/null 2>&1
        echo "100"; echo "XXX"; echo "Build complete!"; echo "XXX"
    } | whiptail --title "Building Server Image" --gauge "Please wait..." 8 78 0

    whiptail --title "Success" --msgbox "Server configuration completed!\n\nYou can now start your server from the main menu." 10 78
}

# Function to show usage
show_usage() {
    echo "Usage: $0 {start|stop|status|restart|logs|lastlog|backup|restore|players|access|cleanup|data|setup|gdrive-sync-setup|gdrive-sync|backup-schedule|backup-reenable|?}"
    echo "  🟢 start             - Start the Valheim server"
    echo "  🔴 stop              - Stop the Valheim server"
    echo "  🟡 status            - Show server status"
    echo "  ♻️  restart           - Restart the server"
    echo "  📜 logs              - Show server logs (follow mode)"
    echo "  📜 lastlog           - Show last 100 lines of logs"
    echo "  📂 backup            - Create a backup"
    echo "  🗃️  restore           - Restore from a previous backup"
    echo "  👥 players           - List all currently connected players"
    echo "  🌐 access            - Check server accessibility"
    echo "  🧹 cleanup           - Remove cache volume and force fresh download"
    echo "  💾 data              - Check data persistence"
    echo "  ⚙️  setup             - Set up server configuration"
    echo "  ☁️  gdrive-sync-setup - Set up or update Google Drive/rclone backup integration"
    echo "  ☁️  gdrive-sync       - Manually sync backup directory to Google Drive"
    echo "  🕒 backup-schedule   - Describe the backup schedule"
    echo "  🔄 backup-reenable   - Start the backup scheduler if it is not running"
    echo "  ❓ ?                 - Show this help message"
    exit 1
}

# Function to check if server is running
is_running() {
    docker ps | grep -q $CONTAINER_NAME
    return $?
}

# Function to create backup
create_backup() {
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"

    # Create timestamp for backup file
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/valheim_backup_${TIMESTAMP}.tar.gz"

    # Create backup
    echo "Creating backup: $BACKUP_FILE"
    tar -czf "$BACKUP_FILE" -C "$VALHEIM_DATA" .

    # Check if backup was successful
    if [ $? -eq 0 ]; then
        echo "Backup created successfully"
    else
        echo "Backup failed!"
        return 1
    fi

    # Remove old backups if we have more than MAX_BACKUPS
    echo "Cleaning up old backups..."
    ls -t "$BACKUP_DIR"/valheim_backup_*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm

    echo "Backup process completed"
    echo "Backup location: $BACKUP_FILE"
    echo "Total backups: $(ls "$BACKUP_DIR"/valheim_backup_*.tar.gz 2>/dev/null | wc -l)/$MAX_BACKUPS"

    # Google Drive/rclone sync
    if [ -n "$RCLONE_REMOTE" ] && [ -n "$RCLONE_PATH" ]; then
        if command -v rclone &>/dev/null; then
            gdrive_sync
        else
            echo "rclone is not installed. Skipping Google Drive backup."
        fi
    fi
    return 0
}

# Function to restore from backup
restore_server() {
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        whiptail --title "Error" --msgbox "Backup directory not found!" 8 78
        return 1
    fi

    # Get list of backups
    local backups=()
    local i=1
    while IFS= read -r backup; do
        local backup_date=$(echo "$backup" | grep -o "[0-9]\{8\}_[0-9]\{6\}")
        local formatted_date=$(date -d "${backup_date:0:8} ${backup_date:9:2}:${backup_date:11:2}:${backup_date:13:2}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        if [ -n "$formatted_date" ]; then
            backups+=("$i" "$formatted_date")
            backup_files[$i]="$backup"
            ((i++))
        fi
    done < <(ls -1t "$BACKUP_DIR"/valheim_backup_*.tar.gz 2>/dev/null)

    # Check if any backups exist
    if [ ${#backups[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No backups found in $BACKUP_DIR" 8 78
        return 1
    fi

    # Show backup selection dialog
    local CHOICE=$(whiptail --title "Restore Backup" --menu "Choose a backup to restore:" 20 78 10 "${backups[@]}" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        return 0
    fi

    # Get the selected backup file
    local BACKUP_FILE="${backup_files[$CHOICE]}"

    # Check if server is running
    if is_running; then
        whiptail --title "Error" --msgbox "Please stop the Valheim server before restoring!\nRun: ./server.sh stop" 8 78
        return 1
    fi

    # Confirm restore
    if ! (whiptail --title "Confirm Restore" --yesno "Are you sure you want to restore from:\n$BACKUP_FILE\n\nThis will overwrite current world data!" 12 78); then
        return 0
    fi

    # Create backup of current data before restore
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local PRERESTORE_BACKUP="$BACKUP_DIR/prerestore_backup_$TIMESTAMP.tar.gz"
    
    # Show progress for pre-restore backup
    {
        echo "0"
        echo "XXX"
        echo "Creating backup of current data..."
        echo "XXX"
        
        tar -czf "$PRERESTORE_BACKUP" -C "$VALHEIM_DATA" . 2>/dev/null
        
        echo "25"
        echo "XXX"
        echo "Clearing current data..."
        echo "XXX"
        
        rm -rf "$VALHEIM_DATA"/*
        
        echo "50"
        echo "XXX"
        echo "Restoring from backup..."
        echo "XXX"
        
        mkdir -p "$VALHEIM_DATA"
        tar -xzf "$BACKUP_FILE" -C "$VALHEIM_DATA"
        
        echo "100"
        echo "XXX"
        echo "Restore completed!"
        echo "XXX"
    } | whiptail --title "Restoring Backup" --gauge "Preparing restore process..." 8 78 0

    if [ $? -eq 0 ]; then
        whiptail --title "Success" --msgbox "Restore completed successfully!\n\nPre-restore backup created at:\n$PRERESTORE_BACKUP" 12 78
        return 0
    else
        whiptail --title "Error" --msgbox "Restore failed!\n\nPre-restore backup available at:\n$PRERESTORE_BACKUP" 12 78
        return 1
    fi
}

# Function to manage the backup scheduler
check_backup_scheduler() {
    # Kill any existing backup loop before starting a new one
    if [ -f /tmp/valheim_backup_pid ]; then
        backup_pid=$(cat /tmp/valheim_backup_pid)
        if kill -0 $backup_pid 2>/dev/null; then
            echo "Killing existing backup loop (PID $backup_pid)..."
            kill $backup_pid
        fi
        rm -f /tmp/valheim_backup_pid
    fi
    
    if is_running; then
        local interval_sec=$(( ${BACKUP_INTERVAL_HOURS:-1} * 3600 ))
        echo "Starting hourly backup scheduler (every ${BACKUP_INTERVAL_HOURS:-1} hour(s))..."
        (
            while true; do
                sleep $interval_sec
                if is_running; then
                    echo "[$(date)] Running scheduled backup..."
                    create_backup
                fi
            done
        ) &
        echo $! > /tmp/valheim_backup_pid
    else
        echo "No running server, backup scheduler not started."
    fi
}

# Function to start server
start_server() {
    if is_running; then
        echo "Server is already running!"
        return 1
    fi
    
    # Check if Docker image exists
    if ! docker image inspect ${IMAGE_NAME}:latest >/dev/null 2>&1; then
        echo "Docker image not found. Building image..."
        docker build -t ${IMAGE_NAME} .
        if [ $? -ne 0 ]; then
            echo "Failed to build Docker image"
            return 1
        fi
    fi
    
    # Check for and remove stopped container with the same name
    if docker ps -a | grep -q $CONTAINER_NAME; then
        echo "Removing existing stopped container..."
        docker rm $CONTAINER_NAME
    fi
    
    # Create cache volume if it doesn't exist
    if ! docker volume ls | grep -q $CACHE_VOLUME; then
        echo "Creating cache volume..."
        docker volume create $CACHE_VOLUME
    fi
    
    # Ensure data directories exist
    setup_data_directories
    
    echo "Starting Valheim server..."
    echo "World data will be stored in: ${VALHEIM_DATA}/worlds_local"
    # Start the server with updated volume mount for dedicated save path
    docker run -d --name $CONTAINER_NAME \
        -p 2456-2458:2456-2458/udp \
        -v "$(pwd)/${VALHEIM_DATA}:/valheimdata" \
        -v "$CACHE_VOLUME:/home/steam/valheim-cache" \
        -e SERVER_NAME="$SERVER_NAME" \
        -e WORLD_NAME="$WORLD_NAME" \
        -e SERVER_PASS="$SERVER_PASS" \
        -e SERVER_PUBLIC=$SERVER_PUBLIC \
        -e SERVER_CROSSPLAY=${SERVER_CROSSPLAY:-0} \
        --restart unless-stopped \
        ${IMAGE_NAME}:latest

    # Start or restart the backup scheduler
    check_backup_scheduler
}

# Function to stop server
stop_server() {
    if ! is_running; then
        echo "Server is not running."
        check_backup_scheduler
        return 0
    fi

    echo "Preparing to stop Valheim server..."
    
    # Create backup before shutdown
    echo "Creating backup before shutdown..."
    create_backup

    # Stop the container
    echo "Stopping Valheim server..."
    if docker stop --timeout=30 $CONTAINER_NAME; then
        echo "Server stopped successfully."
    else
        echo "Warning: Server stop timed out, forcing shutdown..."
        docker kill $CONTAINER_NAME
    fi

    # Verify server is stopped
    if ! is_running; then
        echo "Server is now offline."
    else
        echo "Error: Server is still running! Please check server status."
        return 1
    fi
    # Stop or restart the backup scheduler
    check_backup_scheduler
}

# Function to show status
show_status() {
    if is_running; then
        {
            echo "0"; echo "XXX"; echo "Getting server status..."; echo "XXX"
            
            # Ensure bc is available for calculations
            if ! command -v bc >/dev/null 2>&1; then
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get update && sudo apt-get install -y bc >/dev/null 2>&1
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y bc >/dev/null 2>&1
                elif command -v pacman >/dev/null 2>&1; then
                    sudo pacman -S --noconfirm bc >/dev/null 2>&1
                fi
            fi
            
            # Get container stats
            local stats=""
            local temp_stats=$(mktemp)
            if docker stats --no-stream $CONTAINER_NAME > "$temp_stats" 2>/dev/null; then
                # Skip header line and get stats
                local stats_line=$(tail -n 1 "$temp_stats")
                if [ -n "$stats_line" ]; then
                    local cpu=$(echo "$stats_line" | awk '{print $3}')
                    local mem=$(echo "$stats_line" | awk '{print $4" / "$6}')
                    local net=$(echo "$stats_line" | awk '{print $8" / "$10}')
                    
                    stats="   • CPU: $cpu\n"
                    stats+="   • Memory: $mem\n"
                    stats+="   • Network I/O: $net"
                fi
            fi
            rm -f "$temp_stats"
            
            # Get uptime
            local uptime=""
            local state=$(docker inspect -f '{{.State.Status}} {{.State.StartedAt}}' $CONTAINER_NAME 2>/dev/null)
            if [[ "$state" =~ ^running\ (.+)$ ]]; then
                local started_at="${BASH_REMATCH[1]}"
                local start_seconds=$(date -d "$started_at" +%s 2>/dev/null)
                if [ -n "$start_seconds" ]; then
                    local now_seconds=$(date +%s)
                    local uptime_seconds=$((now_seconds - start_seconds))
                    
                    local days=$((uptime_seconds / 86400))
                    local hours=$(((uptime_seconds % 86400) / 3600))
                    local minutes=$(((uptime_seconds % 3600) / 60))
                    
                    uptime=""
                    [ $days -gt 0 ] && uptime+="$days day$([ $days -ne 1 ] && echo "s") "
                    [ $hours -gt 0 ] && uptime+="$hours hour$([ $hours -ne 1 ] && echo "s") "
                    uptime+="$minutes minute$([ $minutes -ne 1 ] && echo "s")"
                    # Trim trailing space
                    uptime=$(echo "$uptime" | sed 's/ $//')
                else
                    uptime="Unable to calculate"
                fi
            else
                uptime="Unable to determine"
            fi
            
            # Get number of connected players
            local player_count=$(docker logs $CONTAINER_NAME 2>&1 | grep -c "Got character ZDOID from" || echo "0")
            local current_players=$(docker logs $CONTAINER_NAME 2>&1 | grep "Got character ZDOID from" | tail -n $player_count | awk -F "from " '{print $2}' | awk -F " :" '{print $1}' | sort | uniq)
            
            echo "100"; echo "XXX"; echo "Status retrieved!"; echo "XXX"
        } | whiptail --title "Getting Status" --gauge "Please wait..." 8 78 0

        # Build status message
        local status_msg="🟢 Server Status: RUNNING\n"
        status_msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        status_msg+="📋 Server Info:\n"
        status_msg+="   • Name: $SERVER_NAME\n"
        status_msg+="   • World: $WORLD_NAME\n"
        status_msg+="   • Public: $([ "$SERVER_PUBLIC" == "1" ] && echo "Yes" || echo "No")\n"
        status_msg+="   • Crossplay: $([ "$SERVER_CROSSPLAY" == "1" ] && echo "Yes" || echo "No")\n"
        status_msg+="   • Uptime: $uptime\n\n"
        
        if [ -n "$stats" ]; then
            status_msg+="📊 Performance:\n$stats\n\n"
        else
            status_msg+="📊 Performance:\n   • Unable to retrieve performance data\n\n"
        fi
        
        status_msg+="👥 Connected Players:\n"
        if [ -n "$current_players" ]; then
            while IFS= read -r player; do
                status_msg+="   • $player\n"
            done <<< "$current_players"
        else
            status_msg+="   • No players connected\n"
        fi
        
        whiptail --title "Server Status" --msgbox "$status_msg" 20 78
    else
        whiptail --title "Server Status" --msgbox "🔴 Server Status: STOPPED\n\nUse the 'Start Server' option to start the server." 10 78
    fi
}

# Function to list connected players
list_players() {
    if ! is_running; then
        echo "Error: Server is not running"
        return 1
    fi

    # Create temporary files
    TEMP_LOG=$(mktemp)
    TEMP_PLAYERS=$(mktemp)
    DEBUG_LOG=$(mktemp)
    
    # Get all player events and filter Steam messages
    docker logs $CONTAINER_NAME 2>/dev/null | \
        grep -v "\[S_API\]\|\[Steamworks\]\|SteamInternal\|Setting breakpad\|CAppInfo\|Saved\|Shutdown\|Cleanup\|Saving\|Loading\|Loaded\|Spawned\|Destroyed\|Queued\|Processed\|Skipped\|Synced\|Received\|Sent\|Pending\|Finished\|Started\|Stopped\|Updated\|Changed\|Modified\|Initialized\|Registered\|Unregistered" | \
        grep -E "Got connection|Got character ZDOID from|Closing socket" > "$TEMP_LOG"
    
    # Create a temporary file to store Steam ID mappings
    TEMP_STEAMIDS=$(mktemp)
    
    # Process events in chronological order
    while IFS= read -r line; do
        timestamp=$(echo "$line" | cut -d' ' -f1,2)
        
        if echo "$line" | grep -q "Got connection SteamID"; then
            # New Steam connection
            steamid=$(echo "$line" | grep -o "[0-9]\{17\}")
            if [ ! -z "$steamid" ]; then
                # Add or update Steam ID entry (marked as waiting for character)
                echo "$steamid:waiting:$timestamp" > "$TEMP_STEAMIDS.new"
                cat "$TEMP_STEAMIDS" | grep -v "^$steamid:" >> "$TEMP_STEAMIDS.new"
                mv "$TEMP_STEAMIDS.new" "$TEMP_STEAMIDS"
            fi
        elif echo "$line" | grep -q "Got character ZDOID from"; then
            # Player connected with character
            player=$(echo "$line" | awk 'match($0, /.*Got character ZDOID from (.*) : [0-9]+:[0-9]+$/, arr) {print arr[1]}')
            if [ ! -z "$player" ]; then
                # Find the most recent waiting Steam ID
                waiting_steamid=$(grep ":waiting:" "$TEMP_STEAMIDS" | head -n 1 | cut -d: -f1)
                if [ ! -z "$waiting_steamid" ]; then
                    # Update Steam ID entry with player name
                    sed -i "s/$waiting_steamid:waiting:/$waiting_steamid:$player:/" "$TEMP_STEAMIDS"
                    # Add to active players
                    echo "$waiting_steamid:$player:$timestamp" >> "$TEMP_PLAYERS"
                fi
            fi
        elif echo "$line" | grep -q "Closing socket"; then
            # Socket closed - player disconnected
            steamid=$(echo "$line" | grep -o "[0-9]\{17\}")
            if [ ! -z "$steamid" ]; then
                # Remove from active players
                sed -i "/^$steamid:/d" "$TEMP_PLAYERS"
                # Remove from Steam ID mappings
                sed -i "/^$steamid:/d" "$TEMP_STEAMIDS"
            fi
        fi
    done < "$TEMP_LOG"

    # Display current players
    echo "Players Online:"
    if [ -s "$TEMP_PLAYERS" ]; then
        while IFS=: read -r steamid player timestamp; do
            echo "👤 $player"
        done < "$TEMP_PLAYERS"
    else
        echo "No players currently connected"
    fi
    
    # Cleanup temporary files
    rm -f "$TEMP_LOG" "$TEMP_PLAYERS" "$TEMP_STEAMIDS" "$DEBUG_LOG"
}

# Function to check server accessibility
access_server() {
    if ! is_running; then
        if [ -n "$DISPLAY" ] || command -v whiptail >/dev/null 2>&1; then
            whiptail --title "Error" --msgbox "Server is not running.\nPlease start the server first to view access information." 8 78
        else
            printf "Error: Server is not running\n"
            printf "Please start the server first to view access information.\n"
        fi
        return 1
    fi

    # Get server information
    SERVER_IP=$(hostname -I | awk '{print $1}') # Get local IP
    
    # Attempt to get public IP, fallback to N/A if curl fails or returns nothing
    PUBLIC_IP_CURL_OUTPUT=$(curl -s https://api.ipify.org)
    if [ -n "$PUBLIC_IP_CURL_OUTPUT" ]; then
        PUBLIC_IP="$PUBLIC_IP_CURL_OUTPUT"
    else
        PUBLIC_IP="N/A"
    fi

    # Build the message
    local msg
    msg="Valheim Server Access Information\n"
    msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    msg+="🟢 Joining for Internal (LAN) Players:\n"
    if [ -n "$SERVER_IP" ]; then
        msg+="   • Connect to IP: $SERVER_IP:2456\n"
    else
        msg+="   • Could not determine local IP address.\n"
    fi
    msg+="   • Server Name: $SERVER_NAME\n"
    msg+="   • Password: $SERVER_PASS\n\n"

    msg+="🌍 Joining for External (WAN/Internet) Players:\n"
    if [ "$PUBLIC_IP" != "N/A" ]; then
        msg+="   • Your Public IP: $PUBLIC_IP\n"
        msg+="   • Connect to: $PUBLIC_IP:2456\n"
        msg+="   • NOTE: Port forwarding required (UDP 2456-2458)\n"
    else
        msg+="   • Could not determine public IP address\n"
        msg+="   • External access may not be possible\n"
    fi
    msg+="   • Server Name: $SERVER_NAME\n"
    msg+="   • Password: $SERVER_PASS\n\n"
    
    msg+="✨ Port Forwarding:\n"
    msg+="   Forward UDP ports 2456-2458 to local IP: $SERVER_IP"

    # Display the message using whiptail if available, otherwise use printf
    if [ -n "$DISPLAY" ] || command -v whiptail >/dev/null 2>&1; then
        whiptail --title "Server Access Information" --scrolltext --msgbox "$msg" 24 78
    else
        printf "%b" "$msg\n"
    fi
}

# Function to cleanup cache
cleanup_cache() {
    if is_running; then
        echo "Error: Please stop the server before cleaning up the cache"
        echo "Run: ./server.sh stop"
        return 1
    fi

    echo "Removing cache volume..."
    if docker volume ls | grep -q $CACHE_VOLUME; then
        docker volume rm $CACHE_VOLUME
        if [ $? -eq 0 ]; then
            echo "Cache volume removed successfully"
        else
            echo "Failed to remove cache volume"
            return 1
        fi
    else
        echo "Cache volume does not exist"
    fi
}

# Function to check data persistence
check_data_persistence() {
    local world_files=$(ls -la "${VALHEIM_DATA}/worlds_local" 2>/dev/null)
    local char_files=$(ls -la "${VALHEIM_DATA}/characters" 2>/dev/null)
    
    local output="World Files Location: ${VALHEIM_DATA}/worlds_local\n\n"
    output+="Current World Files:\n$world_files\n\n"
    output+="Character Files Location: ${VALHEIM_DATA}/characters\n\n"
    output+="Current Character Files:\n$char_files"
    
    whiptail --title "Data Persistence Check" --scrolltext --msgbox "$output" 24 78
}

# Function to describe the backup schedule in human language
backup_schedule() {
    # Check if the backup scheduler is running
    local scheduler_status="OFF"
    if [ -f /tmp/valheim_backup_pid ]; then
        backup_pid=$(cat /tmp/valheim_backup_pid)
        if kill -0 $backup_pid 2>/dev/null; then
            scheduler_status="ON"
        fi
    fi
    
    cat << EOF
🗂️  Valheim Server Backup Schedule
────────────────────────────────────
🔵 Backup Scheduler: $scheduler_status

⏰ Frequency:
   • Every ${BACKUP_INTERVAL_HOURS:-1} hour(s) while server is running
   • Before server shutdown
   • Manual backups available

💾 Retention:
   • Keeps last $MAX_BACKUPS backups
   • Location: $BACKUP_DIR

☁️  Cloud Sync:
EOF
    if [ -n "$RCLONE_REMOTE" ] && [ -n "$RCLONE_PATH" ]; then
        echo "   • Google Drive sync ENABLED"
        echo "   • Remote: $RCLONE_REMOTE"
        echo "   • Folder: $RCLONE_PATH"
    else
        echo "   • Google Drive sync DISABLED"
    fi
}

# Function to re-enable the backup scheduler if not running
backup_reenable() {
    if [ -f /tmp/valheim_backup_pid ]; then
        backup_pid=$(cat /tmp/valheim_backup_pid)
        if kill -0 $backup_pid 2>/dev/null; then
            echo "🟢 Backup scheduler is already running (PID $backup_pid)."
            return 0
        else
            rm -f /tmp/valheim_backup_pid
        fi
    fi
    if is_running; then
        local interval_sec=$(( ${BACKUP_INTERVAL_HOURS:-1} * 3600 ))
        echo "Starting backup scheduler (every ${BACKUP_INTERVAL_HOURS:-1} hour(s))..."
        (
            while true; do
                sleep $interval_sec
                if is_running; then
                    echo "[$(date)] Running scheduled backup..."
                    create_backup
                fi
            done
        ) &
        echo $! > /tmp/valheim_backup_pid
        echo "🟢 Backup scheduler started (PID $(cat /tmp/valheim_backup_pid))."
    else
        echo "🔴 Server is not running. Start the server first to enable the backup scheduler."
    fi
}

# Function to show output in a scrollable dialog
show_output() {
    local title="$1"
    local text="$2"
    whiptail --title "$title" --scrolltext --msgbox "$text" 20 78
}

# Function to capture command output
capture_output() {
    local output
    output=$(eval "$1" 2>&1)
    echo "$output"
}

# Function to show interactive menu
show_menu() {
    while true; do
        CHOICE=$(whiptail --title "Valheim Server Control" --menu "\nChoose an operation:" 20 78 12 \
            "1"  "Start Server............🟢" \
            "2"  "Stop Server.............🔴" \
            "3"  "Show Server Status......🟡" \
            "4"  "Restart Server..........♻️ " \
            "5"  "List Players............👥" \
            "6"  "View Server Logs........📜" \
            "7"  "Backup Management.......💾" \
            "8"  "Server Settings.........⚙️ " \
            "9"  "Server Access Info......🌐" \
            "10" "Clear All Logs..........🧹" \
            "11" "Exit....................❌" \
            3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            exit 0
        fi

        case $CHOICE in
            "1")
                if is_running; then
                    whiptail --title "Error" --msgbox "Server is already running!" 8 78
                    continue
                fi

                # Request sudo access upfront if needed
                if ! sudo -n true 2>/dev/null; then
                    current_user=$(whoami)
                    password=$(whiptail --title "Sudo Required" \
                        --passwordbox "\nStarting the server requires sudo privileges.\nEnter password for user '$current_user':" \
                        12 78 3>&1 1>&2 2>&3)
                    if [ $? -ne 0 ]; then
                        continue
                    fi
                    # Test sudo access
                    if ! echo "$password" | sudo -S true 2>/dev/null; then
                        whiptail --title "Error" --msgbox "Invalid password for user '$current_user' or sudo access denied." 8 78
                        continue
                    fi
                fi

                # Check if Docker image exists and build if needed
                if ! docker image inspect ${IMAGE_NAME}:latest >/dev/null 2>&1; then
                    {
                        echo "0"; echo "XXX"; echo "Building Docker image..."; echo "XXX"
                        docker build -t ${IMAGE_NAME} . >/dev/null 2>&1
                        echo "33"; echo "XXX"; echo "Docker image built."; echo "XXX"
                    } | whiptail --title "Building Image" --gauge "Please wait..." 8 78 0
                fi

                {
                    echo "0"; echo "XXX"; echo "Preparing to start server..."; echo "XXX"
                    
                    # Remove existing container if it exists
                    if docker ps -a | grep -q $CONTAINER_NAME; then
                        echo "25"; echo "XXX"; echo "Removing old container..."; echo "XXX"
                        docker rm $CONTAINER_NAME >/dev/null 2>&1
                    fi
                    
                    # Create cache volume if needed
                    if ! docker volume ls | grep -q $CACHE_VOLUME; then
                        echo "50"; echo "XXX"; echo "Creating cache volume..."; echo "XXX"
                        docker volume create $CACHE_VOLUME >/dev/null 2>&1
                    fi
                    
                    # Ensure data directories exist with sudo password
                    echo "75"; echo "XXX"; echo "Setting up data directories..."; echo "XXX"
                    mkdir -p "${VALHEIM_DATA}/worlds_local" "${VALHEIM_DATA}/worlds" "${VALHEIM_DATA}/characters" "${VALHEIM_DATA}/saves"
                    if [ -n "$password" ]; then
                        echo "$password" | sudo -S chown -R 1000:1000 "${VALHEIM_DATA}" >/dev/null 2>&1
                    else
                        sudo chown -R 1000:1000 "${VALHEIM_DATA}" >/dev/null 2>&1
                    fi
                    chmod -R u+rwx,g+rwx,o+rx "${VALHEIM_DATA}" >/dev/null 2>&1
                    
                    # Start the server
                    echo "90"; echo "XXX"; echo "Starting Valheim server..."; echo "XXX"
                    # Set up environment variables for the container
                    docker run -d --name $CONTAINER_NAME \
                        -p 2456-2458:2456-2458/udp \
                        -v "$(pwd)/${VALHEIM_DATA}:/valheimdata" \
                        -v "$CACHE_VOLUME:/home/steam/valheim-cache" \
                        -e SERVER_NAME="$SERVER_NAME" \
                        -e WORLD_NAME="$WORLD_NAME" \
                        -e SERVER_PASS="$SERVER_PASS" \
                        -e SERVER_PUBLIC=$SERVER_PUBLIC \
                        -e SERVER_CROSSPLAY=${SERVER_CROSSPLAY:-0} \
                        -e VALHEIM_SAVE_PATH="/valheimdata" \
                        --restart unless-stopped \
                        ${IMAGE_NAME}:latest >/dev/null 2>&1
                    
                    # Log server configuration and environment validation
                    {
                        echo "[DEBUG] Environment Check ($(date)):"
                        echo "Script environment:"
                        echo "  SERVER_NAME='$SERVER_NAME'"
                        echo "  WORLD_NAME='$WORLD_NAME'"
                        echo "  SERVER_PASS='$SERVER_PASS'"
                        echo "  VALHEIM_DATA='$VALHEIM_DATA'"
                        echo "  VALHEIM_SAVE_PATH='/valheimdata'"
                        echo ""
                        echo "Container environment:"
                        docker exec $CONTAINER_NAME env | grep -E "SERVER_|WORLD_|VALHEIM_"
                        echo ""
                        echo "World files:"
                        ls -la "$(pwd)/${VALHEIM_DATA}/worlds_local/" || echo "No world files found"
                    } >> /tmp/valheim_server.log 2>&1
                    
                    # Wait a moment for container to start
                    sleep 2
                    
                    # Clear password from memory
                    if [ -n "$password" ]; then
                        password=""
                        unset password
                    fi
                    
                    echo "100"; echo "XXX"; echo "Server startup complete!"; echo "XXX"
                } | whiptail --title "Starting Server" --gauge "Please wait..." 8 78 0
                
                # Check if server started successfully
                if is_running; then
                    whiptail --title "Success" --msgbox "Server started successfully!\n\nWorld data location: ${VALHEIM_DATA}/worlds_local" 10 78
                else
                    whiptail --title "Error" --msgbox "Failed to start server. Please check logs for details." 8 78
                fi
                ;;
            "2")
                if (whiptail --title "Confirm Stop" --yesno "Are you sure you want to stop the server?" 8 78); then
                    # Request sudo access upfront if needed
                    if ! sudo -n true 2>/dev/null; then
                        current_user=$(whoami)
                        password=$(whiptail --title "Sudo Required" \
                            --passwordbox "\nStopping the server requires sudo privileges.\nEnter password for user '$current_user':" \
                            12 78 3>&1 1>&2 2>&3)
                        if [ $? -ne 0 ]; then
                            continue
                        fi
                        # Test sudo access
                        if ! echo "$password" | sudo -S true 2>/dev/null; then
                            whiptail --title "Error" --msgbox "Invalid password for user '$current_user' or sudo access denied." 8 78
                            continue
                        fi
                    fi

                    {
                        echo "0"; echo "XXX"; echo "Stopping Valheim server..."; echo "XXX"
                        OUTPUT=$(stop_server 2>&1)
                        
                        # Clean up with sudo if needed
                        if [ -n "$password" ]; then
                            echo "$password" | sudo -S chown -R $(whoami):$(whoami) "${VALHEIM_DATA}" >/dev/null 2>&1
                        else
                            sudo chown -R $(whoami):$(whoami) "${VALHEIM_DATA}" >/dev/null 2>&1
                        fi
                        
                        # Clear password from memory
                        if [ -n "$password" ]; then
                            password=""
                            unset password
                        fi
                        
                        echo "100"; echo "XXX"; echo "Server shutdown complete!"; echo "XXX"
                    } | whiptail --title "Stopping Server" --gauge "Please wait..." 8 78 0
                    
                    if ! is_running; then
                        whiptail --title "Success" --msgbox "Server stopped successfully!" 8 78
                    else
                        whiptail --title "Error" --msgbox "Failed to stop server.\n\n$OUTPUT" 12 78
                    fi
                fi
                ;;
            "3")
                show_status
                ;;
            "4")
                if (whiptail --title "Confirm Restart" --yesno "Are you sure you want to restart the server?" 8 78); then
                    {
                        echo "0"; echo "XXX"; echo "Stopping server..."; echo "XXX"
                        stop_server >/dev/null 2>&1
                        echo "33"; echo "XXX"; echo "Waiting for clean shutdown..."; echo "XXX"
                        sleep 5
                        echo "66"; echo "XXX"; echo "Starting server..."; echo "XXX"
                        OUTPUT=$(start_server 2>&1)
                        echo "100"; echo "XXX"; echo "Restart complete!"; echo "XXX"
                    } | whiptail --title "Restarting Server" --gauge "Please wait..." 8 78 0
                    
                    if is_running; then
                        whiptail --title "Success" --msgbox "Server restarted successfully!\n\n$OUTPUT" 12 78
                    else
                        whiptail --title "Error" --msgbox "Failed to restart server.\n\n$OUTPUT" 12 78
                    fi
                fi
                ;;
            "5")
                OUTPUT=$(list_players)
                whiptail --title "Connected Players" --scrolltext --msgbox "$OUTPUT" 20 78
                ;;
            "6")
                LOGS_CHOICE=$(whiptail --title "Server Logs" --menu "Choose log view:" 15 60 4 \
                    "1" "View Last 100 Lines (Filtered)" \
                    "2" "View Live Logs (Filtered)" \
                    "3" "View All Logs (Unfiltered)" \
                    3>&1 1>&2 2>&3)
                
                case $LOGS_CHOICE in
                    "1")
                        OUTPUT=$(docker logs --tail 500 $CONTAINER_NAME 2>&1 | grep -v "WARNING: Shader\|ERROR: Shader\|Fallback handler\|The shader\|The image effect\|UnloadTime:\|Total:\|Unloading\|Couldn't create a Convex Mesh\|The referenced script" | tail -n 100)
                        whiptail --title "Last 100 Log Lines (Filtered)" --scrolltext --msgbox "$OUTPUT" 24 78
                        ;;
                    "2")
                        clear
                        echo "Entering live log view mode (Press Ctrl+C to exit)..."
                        echo "Filtering out shader warnings and debug messages..."
                        sleep 2
                        docker logs -f $CONTAINER_NAME 2>&1 | grep -v "WARNING: Shader\|ERROR: Shader\|Fallback handler\|The shader\|The image effect\|UnloadTime:\|Total:\|Unloading\|Couldn't create a Convex Mesh\|The referenced script"
                        read -p "Press Enter to return to menu..."
                        ;;
                    "3")
                        clear
                        echo "Entering live log view mode (Press Ctrl+C to exit)..."
                        echo "Showing all logs including shader warnings..."
                        sleep 2
                        docker logs -f $CONTAINER_NAME
                        read -p "Press Enter to return to menu..."
                        ;;
                esac
                ;;
            "7")
                while true; do
                    BACKUP_CHOICE=$(whiptail --title "Backup Management" --menu "Choose operation:" 20 78 7 \
                        "1" "Create New Backup" \
                        "2" "Restore from Backup" \
                        "3" "Show Backup Schedule" \
                        "4" "Configure Google Drive Sync" \
                        "5" "Re-enable Backup Scheduler" \
                        "6" "Manual Google Drive Sync" \
                        "7" "Return to Main Menu" \
                        3>&1 1>&2 2>&3)
                    
                    [ $? -ne 0 ] && break
                    
                    case $BACKUP_CHOICE in
                        "1")
                            OUTPUT=$(capture_output "create_backup")
                            show_output "Create Backup" "$OUTPUT"
                            ;;
                        "2")
                            clear
                            restore_server
                            read -p "Press Enter to continue..."
                            ;;
                        "3")
                            OUTPUT=$(capture_output "backup_schedule")
                            show_output "Backup Schedule" "$OUTPUT"
                            ;;
                        "4")
                            clear
                            backup_storage_setup
                            read -p "Press Enter to continue..."
                            ;;
                        "5")
                            OUTPUT=$(capture_output "backup_reenable")
                            show_output "Backup Scheduler" "$OUTPUT"
                            ;;
                        "6")
                            if [ -z "$RCLONE_REMOTE" ] || [ -z "$RCLONE_PATH" ]; then
                                whiptail --title "Error" --msgbox "Google Drive sync is not configured.\nPlease configure it first." 10 78
                            else
                                {
                                    echo "0"; echo "XXX"; echo "Starting manual sync to Google Drive..."; echo "XXX"
                                    rclone sync -P --transfers=3 "$BACKUP_DIR" "$RCLONE_REMOTE:$RCLONE_PATH/" 2>&1
                                    echo "100"; echo "XXX"; echo "Sync completed!"; echo "XXX"
                                } | whiptail --title "Google Drive Sync" --gauge "Syncing backups to Google Drive..." 8 78 0
                                whiptail --title "Success" --msgbox "Manual sync to Google Drive completed!\n\nLocal: $BACKUP_DIR\nRemote: $RCLONE_REMOTE:$RCLONE_PATH/" 10 78
                            fi
                            ;;
                        "7")
                            break
                            ;;
                    esac
                done
                ;;
            "8")
                if (whiptail --title "Server Settings" --yesno "This will modify your server configuration. Continue?" 8 78); then
                    clear
                    setup_server_config
                    read -p "Press Enter to continue..."
                fi
                ;;
            "9")
                if ! is_running; then
                    whiptail --title "Error" --msgbox "Server is not running.\nPlease start the server first to view access information." 8 78
                    continue
                fi
                
                {
                    echo "0"; echo "XXX"; echo "Getting server information..."; echo "XXX"
                    
                    # Get server information
                    SERVER_IP=$(hostname -I | awk '{print $1}') # Get local IP
                    
                    # Attempt to get public IP
                    PUBLIC_IP_CURL_OUTPUT=$(curl -s https://api.ipify.org)
                    if [ -n "$PUBLIC_IP_CURL_OUTPUT" ]; then
                        PUBLIC_IP="$PUBLIC_IP_CURL_OUTPUT"
                    else
                        PUBLIC_IP="N/A"
                    fi
                    
                    echo "100"; echo "XXX"; echo "Information retrieved!"; echo "XXX"
                } | whiptail --title "Getting Access Info" --gauge "Please wait..." 8 78 0

                # Build the message
                local msg
                msg="Valheim Server Access Information\n"
                msg+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
                
                msg+="🟢 Joining for Internal (LAN) Players:\n"
                if [ -n "$SERVER_IP" ]; then
                    msg+="   • Connect to IP: $SERVER_IP:2456\n"
                else
                    msg+="   • Could not determine local IP address.\n"
                fi
                msg+="   • Server Name: $SERVER_NAME\n"
                msg+="   • Password: $SERVER_PASS\n\n"

                msg+="🌍 Joining for External (WAN/Internet) Players:\n"
                if [ "$PUBLIC_IP" != "N/A" ]; then
                    msg+="   • Your Public IP: $PUBLIC_IP\n"
                    msg+="   • Connect to: $PUBLIC_IP:2456\n"
                    msg+="   • NOTE: Port forwarding required (UDP 2456-2458)\n"
                else
                    msg+="   • Could not determine public IP address\n"
                    msg+="   • External access may not be possible\n"
                fi
                msg+="   • Server Name: $SERVER_NAME\n"
                msg+="   • Password: $SERVER_PASS\n\n"
                
                msg+="✨ Port Forwarding:\n"
                msg+="   Forward UDP ports 2456-2458 to local IP: $SERVER_IP"

                whiptail --title "Server Access Information" --scrolltext --msgbox "$msg" 24 78
                ;;
            "10")
                if (whiptail --title "Clear Logs" --yesno "Clear both debug and container logs?" 8 78); then
                    rm -f /tmp/valheim_server.log
                    if is_running; then
                        docker logs -f $CONTAINER_NAME >/dev/null 2>&1 &
                        LOGGER_PID=$!
                        docker container stop $CONTAINER_NAME >/dev/null 2>&1
                        docker container start $CONTAINER_NAME >/dev/null 2>&1
                        kill $LOGGER_PID >/dev/null 2>&1
                    else
                        docker container rm $CONTAINER_NAME >/dev/null 2>&1
                    fi
                    whiptail --title "Success" --msgbox "All logs have been cleared." 8 78
                fi
                ;;
            "11")
                if (whiptail --title "Confirm Exit" --yesno "Are you sure you want to exit?" 8 78); then
                    exit 0
                fi
                ;;
        esac
    done
}

# Ask-only-once setup logic using .valheim.env
INITIAL_SETUP_ASKED=0
if [ -f .valheim.env ]; then
    source .valheim.env
    # Check if we have the required configuration variables
    if [ -n "$SERVER_NAME" ] && [ -n "$WORLD_NAME" ] && [ -n "$SERVER_PASS" ]; then
        INITIAL_SETUP_ASKED=1
    fi
fi

if [ "$INITIAL_SETUP_ASKED" != "1" ]; then
    if command -v whiptail >/dev/null 2>&1; then
        if whiptail --title "Initial Setup" --yesno "Would you like to run the server configuration process now?" 10 78; then
            setup_server_config
            # Only set INITIAL_SETUP_ASKED=1 after successful setup
            grep -v '^INITIAL_SETUP_ASKED=' .valheim.env 2>/dev/null > .valheim.env.tmp || true
            mv .valheim.env.tmp .valheim.env 2>/dev/null || true
            echo "INITIAL_SETUP_ASKED=1" >> .valheim.env
            exit 0
        else
            # If user declines setup, still mark as asked but not completed
            grep -v '^INITIAL_SETUP_ASKED=' .valheim.env 2>/dev/null > .valheim.env.tmp || true
            mv .valheim.env.tmp .valheim.env 2>/dev/null || true
            echo "INITIAL_SETUP_ASKED=0" >> .valheim.env
            exit 0
        fi
    else
        echo "Would you like to run the server configuration process now? (y/n): "
        read yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            setup_server_config
            # Only set INITIAL_SETUP_ASKED=1 after successful setup
            grep -v '^INITIAL_SETUP_ASKED=' .valheim.env 2>/dev/null > .valheim.env.tmp || true
            mv .valheim.env.tmp .valheim.env 2>/dev/null || true
            echo "INITIAL_SETUP_ASKED=1" >> .valheim.env
            exit 0
        else
            # If user declines setup, still mark as asked but not completed
            grep -v '^INITIAL_SETUP_ASKED=' .valheim.env 2>/dev/null > .valheim.env.tmp || true
            mv .valheim.env.tmp .valheim.env 2>/dev/null || true
            echo "INITIAL_SETUP_ASKED=0" >> .valheim.env
            exit 0
        fi
    fi
fi

# Validate configuration
validate_config() {
    local error=0
    
    if [ -z "$SERVER_NAME" ]; then
        echo "Error: SERVER_NAME cannot be empty"
        error=1
    fi
    
    if [ -z "$WORLD_NAME" ]; then
        echo "Error: WORLD_NAME cannot be empty"
        error=1
    fi
    
    if [ ${#SERVER_PASS} -lt 5 ]; then
        echo "Error: SERVER_PASS must be at least 5 characters long"
        error=1
    fi
    
    if [ "$SERVER_PUBLIC" != "0" ] && [ "$SERVER_PUBLIC" != "1" ]; then
        echo "Error: SERVER_PUBLIC must be 0 or 1"
        error=1
    fi

    if [ "${SERVER_CROSSPLAY:-0}" != "0" ] && [ "${SERVER_CROSSPLAY:-0}" != "1" ]; then
        echo "Error: SERVER_CROSSPLAY must be 0 or 1"
        error=1
    fi

    if [ $error -eq 1 ]; then
        exit 1
    fi
}

# Call validation before any operation
validate_config

# Main script
if [ $# -eq 0 ]; then
    # No arguments provided, show interactive menu
    show_menu
else
    # Arguments provided, handle traditional command-line usage
    case "$1" in
        start)
            start_server
            ;;
        stop)
            stop_server
            ;;
        status)
            show_status
            ;;
        restart)
            stop_server && sleep 5 && start_server
            ;;
        logs)
            docker logs -f $CONTAINER_NAME
            ;;
        lastlog)
            docker logs --tail 100 $CONTAINER_NAME
            ;;
        backup)
            create_backup
            ;;
        restore)
            restore_server
            ;;
        players)
            list_players
            ;;
        access)
            access_server
            ;;
        cleanup)
            cleanup_cache
            ;;
        setup)
            setup_server_config
            ;;
        data)
            check_data_persistence
            ;;
        gdrive-sync-setup)
            backup_storage_setup
            ;;
        gdrive-sync)
            gdrive_sync
            ;;
        backup-schedule)
            backup_schedule
            ;;
        backup-reenable)
            backup_reenable
            ;;
        "?")
            show_usage
            ;;
        *)
            show_usage
            ;;
    esac 
fi 
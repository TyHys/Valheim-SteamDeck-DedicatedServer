#!/bin/bash

# =====================
# Server Configuration
# =====================
# Required settings - modify these for your server
SERVER_NAME="MY_SERVER"          # The name that appears in the server browser
WORLD_NAME="MY_WORLD"             # The name of your world
SERVER_PASS="MY_PASSWORD"            # Must be at least 5 characters
SERVER_PUBLIC=1                # 1 for public, 0 for private

# Advanced settings - change only if you know what you're doing
CONTAINER_NAME="valheim-server"
VALHEIM_DATA="./valheim-data"
BACKUP_DIR="./valheim-backups"
MAX_BACKUPS=24                 # Keep last 24 backups
CACHE_VOLUME="valheim-cache"   # Docker volume for caching

# Ensure data directories exist with correct permissions
setup_data_directories() {
    echo "Setting up data directories..."
    # Create the directory structure for the -savedir path
    mkdir -p "${VALHEIM_DATA}/worlds_local"
    mkdir -p "${VALHEIM_DATA}/worlds"
    mkdir -p "${VALHEIM_DATA}/characters"
    mkdir -p "${VALHEIM_DATA}/saves"
    # Attempt to set ownership to UID 1000, GID 1000 (common for default user / steam user)
    # This might require sudo if the script runner doesn't own the files or isn't root
    sudo chown -R 1000:1000 "${VALHEIM_DATA}" || echo "Warning: Failed to chown ${VALHEIM_DATA}. Manual permission adjustment may be needed."
    chmod -R u+rwx,g+rwx,o+rx "${VALHEIM_DATA}"
}

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
    
    if [ $error -eq 1 ]; then
        exit 1
    fi
}

# Call validation before any operation
validate_config

# DNS_NAME="valheim.imdy.in"  # Your DNS name

# Function to show usage
show_usage() {
    echo "Usage: $0 {start|stop|status|restart|logs|lastlog|backup|restore|players|check|cleanup|data|?}"
    echo "  start    - Start the Valheim server"
    echo "  stop     - Stop the Valheim server"
    echo "  status   - Show server status"
    echo "  restart  - Restart the server"
    echo "  logs     - Show server logs (follow mode)"
    echo "  lastlog  - Show last 100 lines of logs"
    echo "  backup   - Create a backup"
    echo "  restore  - Restore from a previous backup"
    echo "  players  - List all currently connected players"
    echo "  check    - Check server accessibility"
    echo "  data     - Check data persistence"
    echo "  cleanup  - Remove cache volume and force fresh download"
    echo "  ?        - Show this help message"
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
    BACKUP_FILE="$BACKUP_DIR/valheim_backup_$TIMESTAMP.tar.gz"

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
    
    return 0
}

# Function to restore from backup
restore_server() {
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "Backup directory not found!"
        return 1
    fi

    # List available backups
    echo "Available backups:"
    ls -1t "$BACKUP_DIR"/valheim_backup_*.tar.gz 2>/dev/null | nl || { echo "No backups found"; return 1; }

    # If no backups exist, exit
    if [ ! "$(ls -A $BACKUP_DIR/valheim_backup_*.tar.gz 2>/dev/null)" ]; then
        return 1
    fi

    # Ask which backup to restore
    echo -e "\nEnter the number of the backup to restore (or 'q' to quit):"
    read -r choice

    # Exit if user chooses to quit
    if [ "$choice" = "q" ]; then
        echo "Restore cancelled"
        return 0
    fi

    # Get the selected backup file
    BACKUP_FILE=$(ls -1t "$BACKUP_DIR"/valheim_backup_*.tar.gz 2>/dev/null | sed -n "${choice}p")

    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Invalid selection!"
        return 1
    fi

    # Check if server is running
    if is_running; then
        echo "Error: Please stop the Valheim server before restoring!"
        echo "Run: ./server.sh stop"
        return 1
    fi

    # Create backup of current data before restore
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    PRERESTORE_BACKUP="$BACKUP_DIR/prerestore_backup_$TIMESTAMP.tar.gz"
    echo "Creating backup of current data: $PRERESTORE_BACKUP"
    tar -czf "$PRERESTORE_BACKUP" -C "$VALHEIM_DATA" . || echo "Warning: Failed to create pre-restore backup"

    # Clear current data
    echo "Clearing current data..."
    rm -rf "$VALHEIM_DATA"/*

    # Restore from backup
    echo "Restoring from backup: $BACKUP_FILE"
    mkdir -p "$VALHEIM_DATA"
    tar -xzf "$BACKUP_FILE" -C "$VALHEIM_DATA"

    if [ $? -eq 0 ]; then
        echo "Restore completed successfully"
        return 0
    else
        echo "Restore failed!"
        return 1
    fi
}

# Function to start server
start_server() {
    if is_running; then
        echo "Server is already running!"
        return 1
    fi
    
    # Check if Docker image exists
    if ! docker image inspect valheim-server:latest >/dev/null 2>&1; then
        echo "Docker image not found. Building image..."
        export DOCKER_BUILDKIT=1
        docker build -t valheim-server .
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
    # Debug: Print the password value
    echo "Debug: SERVER_PASS value is: $SERVER_PASS"
    # Debug: Print full docker command
    echo "Debug: Running command:"
    set -x
    # Start the server with updated volume mount for dedicated save path
    docker run -d --name $CONTAINER_NAME \
        -p 2456-2458:2456-2458/udp \
        -v "$(pwd)/${VALHEIM_DATA}:/valheimdata" \
        -v "$CACHE_VOLUME:/home/steam/valheim-cache" \
        -e SERVER_NAME="$SERVER_NAME" \
        -e WORLD_NAME="$WORLD_NAME" \
        -e SERVER_PASS="$SERVER_PASS" \
        -e SERVER_PUBLIC=$SERVER_PUBLIC \
        --restart unless-stopped \
        valheim-server:latest
    set +x

    # Start hourly backup in background
    (
        while true; do
            sleep 3600  # Wait for 1 hour
            if is_running; then
                echo "[$(date)] Running hourly backup..."
                create_backup
            fi
        done
    ) &
    echo $! > /tmp/valheim_backup_pid
}

# Function to stop server
stop_server() {
    if ! is_running; then
        echo "Server is not running."
        return 0
    fi

    echo "Preparing to stop Valheim server..."
    
    # Stop the hourly backup process if running
    if [ -f /tmp/valheim_backup_pid ]; then
        backup_pid=$(cat /tmp/valheim_backup_pid)
        if kill -0 $backup_pid 2>/dev/null; then
            echo "Stopping hourly backup process..."
            kill $backup_pid
        fi
        rm -f /tmp/valheim_backup_pid
    fi
    
    # Create backup before shutdown
    echo "Creating backup before shutdown..."
    create_backup

    # Stop the container
    echo "Stopping Valheim server..."
    if docker stop --time=30 $CONTAINER_NAME; then
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
}

# Function to show status
show_status() {
    if is_running; then
        echo "Server status: RUNNING"
        echo "Container stats:"
        docker stats $CONTAINER_NAME --no-stream
        echo -e "\nServer ports:"
        ss -panu | grep :245
    else
        echo "Server status: STOPPED"
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
            player=$(echo "$line" | sed 's/.*Got character ZDOID from \([^ :]*\).*/\1/')
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
check_server() {
    if ! is_running; then
        echo "Error: Server is not running"
        return 1
    fi

    echo "Checking Valheim server accessibility..."
    echo "----------------------------------------"
    
    # Get public IP
    echo "🌐 Public IP:"
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    echo "   $PUBLIC_IP"
    echo ""
    
    # Check local port bindings
    echo "🔌 Local port bindings:"
    for PORT in 2456 2457 2458; do
        if netstat -ulpn 2>/dev/null | grep -q ":$PORT"; then
            echo "   ✅ Port $PORT (UDP) is bound locally"
        else
            echo "   ❌ Port $PORT (UDP) is NOT bound locally"
        fi
    done
    echo ""
    
    # Check if ports are reachable from outside
    echo "🌍 External port check:"
    echo "   Testing connection to ports 2456-2458..."
    echo "   You can test your server from: https://www.yougetsignal.com/tools/open-ports/"
    echo "   - Enter your IP: $PUBLIC_IP"
    echo "   - Test ports: 2456, 2457, and 2458"
    echo ""
    
    # Show Steam query info if available
    echo "🎮 Steam server info:"
    if command -v steamcmd &> /dev/null; then
        steamcmd +login anonymous +query_port $PUBLIC_IP:2457 +quit
    else
        echo "   Install steamcmd to query server info"
        echo "   sudo apt-get install steamcmd"
    fi
    echo ""
    
    echo "✨ Connection information for players:"
    echo "   Server IP: $PUBLIC_IP:2456"
    echo "   Name: $SERVER_NAME"
    echo "   Password: $SERVER_PASS"
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

# Add a new function to check data persistence
check_data_persistence() {
    echo "Checking data persistence..."
    echo "World files location: ${VALHEIM_DATA}/worlds_local"
    echo "Current world files:"
    ls -la "${VALHEIM_DATA}/worlds_local"
    echo
    echo "Other save-related files (characters, etc.) are in: ${VALHEIM_DATA}/"
    echo "Current character files (example):" # Valheim might save characters under a 'characters' subfolder or directly if not further specified by game.
    ls -la "${VALHEIM_DATA}/characters" # Assuming characters are in a subfolder as per our setup_data_directories
}

# Main script
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
    check)
        check_server
        ;;
    data)
        check_data_persistence
        ;;
    cleanup)
        cleanup_cache
        ;;
    "?")
        show_usage
        ;;
    *)
        show_usage
        ;;
esac 
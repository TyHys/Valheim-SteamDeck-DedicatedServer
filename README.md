<p align="center">
  <img src="https://i.imgur.com/mxNfTCZ.png" alt="Valheim Server Banner">
</p>

# Valheim Steam Deck Dedicated Server (SDDS)

This repository contains scripts and configuration for running a lightweight vanilla Valheim dedicated server on your Steam Deck. The server runs in a Docker container with persistent storage and includes features for server management, backups, and player monitoring. It is intended to simplify standup using as few dependencies as possible to decrease resource draw.

This may be ran on non-Steam Deck devices, but issues logged for these devices will be closed & ignored within this repository. This will run fine on anything that can run Docker containers, but some of the commands in this readme would need to be adjusted accordingly.

**Running this server on your Steam Deck will not prevent you from launching Valheim on your Steam account. Some Steam applications can be downloaded "anonymously" (such as the Valheim Dedicated server). This server will run in a container, utilizing this anonymous mode.**


## Prerequisites

1. Steam Deck in Desktop Mode
2. Install Git (If not installed ➡️ Open 'Konsole' from the main menu):
   ```bash
   sudo pacman -S git
   ```
3. Install Docker (If not installed ➡️ Open 'Konsole' from the main menu):
   ```bash
   sudo pacman -S docker
   sudo systemctl enable docker
   sudo systemctl start docker
   sudo usermod -aG docker deck
   newgrp docker
   ```

## Initial Setup

1. Clone this repository - This will be the location of your server data & backups on your Steam Deck. To easily select a folder, open it in the file explorer. You can right click in the folder and select "Open Terminal Here" before running the below commands.
   ```bash
   git clone https://github.com/TyHys/Valheim-SteamDeck-DedicatedServer.git
   cd Valheim-SteamDeck-DedicatedServer
   ```

2. Run the interactive setup (this will prompt for your server settings and build the Docker image):
   ```bash
   ./server.sh setup
   ```

3. Start the server:
   ```bash
   ./server.sh start
   ```

## Server Management

The `server.sh` script provides several commands for managing your server:

```bash
./server.sh {command}

Commands:
  start    - Start the Valheim server
  stop     - Stop the Valheim server
  status   - Show server status
  restart  - Restart the server
  logs     - Show server logs (follow mode)
  lastlog  - Show last 100 lines of logs
  backup   - Create a backup
  chat     - Send message to all players
  players  - List all currently connected players
  check    - Check server accessibility
  setup    - Interactive server configuration and image build
  backup-storage - Set up or update Google Drive/rclone backup integration
  ?        - Show this help message
```

## Port Forwarding

For players to connect from outside your network, forward these UDP ports in your router:
- 2456 (Game port)
- 2457 (Steam query port)
- 2458 (Steam networking)

## Backup System

The server automatically:
- Creates backups every hour while running
- Creates a backup before shutdown
- Keeps the last 24 backups
- Stores backups in ./valheim-backups

Manual backup:
```bash
./server.sh backup
```

### Google Drive Backup (Optional)

You can automatically upload your backups to Google Drive using [rclone](https://rclone.org/):

1. Run the setup command and choose to set up Google Drive backup when prompted, **or** run:
   ```bash
   ./server.sh backup-storage
   ```
   at any time to set up or update your Google Drive/rclone integration.
2. Follow the prompts to configure rclone and specify your Google Drive remote and backup folder.
3. After setup, all new backups will be automatically uploaded to your Google Drive.

> **Note:** You must have `rclone` installed. On Steam Deck:
> ```bash
> sudo pacman -S rclone
> ```
> Or see [rclone.org/install](https://rclone.org/install/) for other platforms.

## Monitoring

Check server status:
```bash
./server.sh status
```

View connected players:
```bash
./server.sh players
```

Check server accessibility:
```bash
./server.sh check
```

## File Structure

```
.
├── README.md           # This documentation
├── Dockerfile         # Docker image configuration
├── server.sh          # Main server management script
├── valheim-data/      # Server world data (persistent)
└── valheim-backups/   # Backup storage
```

## About This Project

This project was developed and tested on a Steam Deck running SteamOS. It provides a complete solution for running a dedicated Valheim server directly from your Steam Deck, including:

- Docker containerization for easy deployment
- Automated backup system
- In-game commands for players
- Server management scripts
- Performance optimizations for Steam Deck

The server can be run while your Steam Deck is docked or undocked, though a docked configuration with ethernet connection is recommended for optimal performance.

## License

This project is open source and available under the MIT License.

## Acknowledgments

- Valheim game by Iron Gate AB
- Steam Deck by Valve Corporation
- Docker container technology

## Support

If you encounter any issues or have suggestions for improvements, please:
1. Check the [Issues](https://github.com/TyHys/Valheim-SteamDeck-DedicatedServer/issues) page
2. Create a new issue if your problem isn't already reported
3. Provide as much detail as possible, including:
   - Steam Deck model
   - SteamOS version
   - Error messages
   - Steps to reproduce

## Troubleshooting

1. **Server won't start**
   - Check logs: `./server.sh logs`
   - Ensure ports aren't in use: `netstat -tulpn | grep 245`
   - Verify Docker is running: `systemctl status docker`

2. **Players can't connect**
   - Run: `./server.sh check` to get your public IP & verify port setup. This will not always correctly check the ports, so test with another person.
   - Ensure UDP ports 2456-2458 are forwarded

3. **Performance Issues**
   - Monitor system resources: `htop`
   - Check disk space: `df -h`
   - View server logs: `./server.sh logs`

## Steam Deck-Specific Notes

1. **Power Management**
   - Keep your Steam Deck plugged in when running the server
   - Disable auto-sleep in Desktop Mode
   - Consider using a USB-C dock for better cooling

2. **Network**
   - Ethernet connection recommended (via USB-C dock)
   - If using WiFi, stay close to router
   - Static IP recommended

3. **Storage**
   - Monitor available space regularly
   - World files stored in: ./valheim-data
   - Backups in: ./valheim-backups

## Security Notes

1. Choose a strong server password
2. Regularly check logs for unusual activity
3. Keep your Steam Deck's system updated
4. Back up your world data regularly

## Contributing

Feel free to submit issues and enhancement requests! 
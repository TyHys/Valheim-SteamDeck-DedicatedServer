<p align="center">
  <img src="https://i.imgur.com/mxNfTCZ.png" alt="Valheim Server Banner">
</p>

# Valheim Steam Deck Dedicated Server (SDDS)

This project provides scripts and configuration for running a lightweight vanilla Valheim dedicated server on your Steam Deck (or any Linux device with Docker). It features an interactive menu, automated backups, Google Drive integration, and robust server management.

---

## Table of Contents
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Usage](#usage)
  - [Menu-Driven (Recommended)](#menu-driven-recommended)
  - [Command-Line (Alternative)](#command-line-alternative)
- [Backup Management](#backup-management)
- [Google Drive Integration](#google-drive-integration)
- [Permissions & Sudo](#permissions--sudo)
- [Troubleshooting](#troubleshooting)
- [Advanced](#advanced)
- [File Structure](#file-structure)
- [License](#license)
- [Acknowledgments](#acknowledgments)
- [Support](#support)

---

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

2. You will be prompted to configure the server on first launch:
   ```bash
   ./server.sh
   ```


3. Start the server:
   ```bash
    Select "Start Server" from the ./server.sh menu
    Or: by command line "./server.sh start"
   ```

---

> **Configuration note:**
> - You can re-run the setup at any time via `./server.sh setup`
> - You can also re-run the setup via `./server.sh` ⇨ "Server Settings" .

---

## Usage

### Menu-Driven (Recommended)

The easiest way to manage your server is through the interactive menu. Simply run:
```bash
./server.sh
```

<p align="center">
  <img src="https://i.imgur.com/lmC97We.png" alt="Valheim Server Banner">
</p>


This launches an interactive menu for all server management tasks, including:
- Start Server
- Stop Server
- Show Server Status
- Restart Server
- List Players
- View Server Logs (filtered/unfiltered/live)
- Backup Management (sub-menu):
  - Create New Backup
  - Restore from Backup
  - Show Backup Schedule
  - Configure Google Drive Sync
  - Re-enable Backup Scheduler
  - Manual Google Drive Sync
- Server Settings
- Server Access Info
- Clear All Logs
- Exit

### Command-Line (Alternative)

If you prefer using command-line arguments, you can run specific commands directly:
```bash
./server.sh {start|stop|status|restart|logs|lastlog|backup|restore|players|access|cleanup|data|setup|gdrive-sync-setup|gdrive-sync|backup-schedule|backup-reenable|?}
```

For example:
```bash
./server.sh start
./server.sh backup
./server.sh gdrive-sync
```

**Command descriptions:**
- `start`             - Start the Valheim server
- `stop`              - Stop the Valheim server
- `status`            - Show server status
- `restart`           - Restart the server
- `logs`              - Show server logs (follow mode)
- `lastlog`           - Show last 100 lines of logs
- `backup`            - Create a backup
- `restore`           - Restore from a previous backup
- `players`           - List all currently connected players
- `access`            - Show server access information
- `cleanup`           - Remove cache volume and force fresh download
- `data`              - Check data persistence
- `setup`             - Run interactive server configuration
- `gdrive-sync-setup` - Set up or update Google Drive/rclone backup integration
- `gdrive-sync`       - Manually sync backup directory to Google Drive
- `backup-schedule`   - Show a human-readable description of the backup schedule
- `backup-reenable`   - Start the backup scheduler if it is not running
- `?`                 - Show help message

> **Note:** While command-line options are available, using the interactive menu (`./server.sh`) is recommended for most users as it provides a more user-friendly interface and helps prevent errors.

---

## Backup Management

- **Automatic backups:** Created every N hour(s) (configurable during setup) while the server is running and before shutdown.
- **Manual backup:**
  ```bash
  ./server.sh backup
  Or use the 'Backup Management' from the main menu
  ```
- **Restore from backup:**
  ```bash
  ./server.sh restore
  Or use the 'Backup Management' from the main menu
  ```
- **Backup retention:** Keeps the last N backups (configurable during setup).
- **Backup location:** `./valheim-backups` by default.

---

## Google Drive Integration

- **Setup:**
  - Use the menu or run:
    ```bash
    ./server.sh gdrive-sync-setup
    ```
  - The script will guide you through rclone remote creation and authentication (including manual code copy-paste for WSL/remote setups).
- **Manual sync:**
  - Use the menu or run:
    ```bash
    ./server.sh gdrive-sync
    ```
- **Re-enable backup scheduler:**
  - Use the menu or run:
    ```bash
    ./server.sh backup-reenable
    ```

---

## Permissions & Sudo

- Some actions (starting/stopping the server, managing data directories) require sudo privileges.
- The script will prompt for your password if needed.

---

## Troubleshooting

- **Missing dependencies:**
  - If you see errors about missing Docker, rclone, or whiptail, install them as prompted.
- **Reset configuration:**
  - Delete `.valheim.env` and re-run `./server.sh` to start fresh.
- **Server won't start:**
  - Check logs: `./server.sh logs`
  - Verify Docker is running: `systemctl status docker`
- **Players can't connect:**
  - Run: `./server.sh access` to get connection info.
  - Ensure UDP ports 2456-2458 are forwarded to your server's local IP.
- **Google Drive OAuth issues:**
  - If using WSL/SSH, always answer `n` to the browser prompt and use the manual code method.
  - See [rclone remote setup docs](https://rclone.org/remote_setup/) for more help.

---

## Advanced

- **Manual config:** You can edit `.valheim.env` directly if needed.
- **SSH keys for GitHub:**
  - [GitHub Docs: Adding a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)
- **Custom Docker image:** Edit `Dockerfile` as needed.

---

## File Structure

```
.
├── README.md           # This documentation
├── Dockerfile          # Docker image configuration
├── entrypoint.sh        # Container entrypoint (launches the server, handles crossplay flag)
├── server.sh           # Main server management script
├── valheim-data/       # Server world data (persistent)
├── valheim-backups/    # Backup storage
└── .valheim.env        # Server configuration (auto-generated)
```

---

## Valheim 1.0 Notes

- **World save format:** As of the 1.0 release (September 9, 2026), worlds are no longer a single `.db`/`.fwl` file pair. Each world is now a **folder** (named after the world, case-sensitive) inside `worlds_local/`, containing `_main.N.db2`, `_main.N.fwl2`, a `.chunks` index, and individual terrain `.chunk` files. `WORLD_NAME` must match the folder name exactly.
  - Older `.db`/`.fwl` worlds are converted automatically on first load (a backup of the originals is made first). This can take several minutes with no console output — don't stop the server mid-conversion.
  - Backups and restores always operate on the entire world folder; the scripts here already back up the whole data directory, so no changes were needed there.
- **Crossplay:** Set `SERVER_CROSSPLAY=1` in `.valheim.env` (or answer "yes" during `./server.sh setup`) to open the server to PlayStation, Switch, and Xbox players via PlayFab matchmaking, in addition to Steam. It is off by default.
- **Steam app ID and ports are unchanged** (`896660`, UDP `2456-2458`), so rebuilding the Docker image (`docker build`) is sufficient to pull the latest 1.0 patch of the dedicated server via `steamcmd`.

---

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
   - Verify Docker is running: `systemctl status docker`

2. **Players can't connect**
   - Run: `./server.sh access` to get your server's IP addresses and connection instructions.
   - For external connections, ensure UDP ports 2456-2458 are correctly forwarded in your router/firewall to the server's local IP address (shown in `./server.sh access`).

3. **Performance Issues**
   - Monitor system resources: `htop`
   - Check disk space: `df -h`
   - View server logs: `./server.sh logs`

4. **`./server.sh gdrive-sync` won't complete**
   - Interrupt the sync (CTRL + C)
   - Restart it
   - Google Drive is giving you a rate limit for transfers on your account. 
      - Restarting it as a new transfer is the simplest way to remedy this.

## Steam Deck-Specific Notes

1. **Power Management**
   - Keep your Steam Deck plugged in when running the server
   - Disable auto-sleep in Desktop Mode
   - Consider using a USB-C dock for better cooling

2. **Network**
   - Ethernet connection recommended (via USB-C dock)
   - If using WiFi, stay close to router
   - A static IP for your Steam Deck on your local network is recommended for easier port forwarding.

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
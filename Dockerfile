# Base image for building
FROM cm2network/steamcmd:root AS steamcmd

# Set environment variables
ENV STEAM_APPID=896660
ENV VALHEIM_DIR="/home/steam/valheim"
ENV CACHE_DIR="/home/steam/valheim-cache"

# Create directories and set permissions
RUN mkdir -p ${VALHEIM_DIR} && \
    mkdir -p ${CACHE_DIR} && \
    chown -R steam:steam /home/steam

# Switch to steam user for installation
USER steam
WORKDIR /home/steam

# Install Valheim Dedicated Server
# steamcmd's anonymous login intermittently fails PICS/license checks with a generic
# "Missing configuration" error (observed around the Valheim 1.0 launch); retry with
# backoff since these failures are transient on Steam's side, not local.
RUN mkdir -p ~/.steam && \
    for i in 1 2 3 4 5; do \
        /home/steam/steamcmd/steamcmd.sh +force_install_dir ${VALHEIM_DIR} +login anonymous +app_update ${STEAM_APPID} validate +quit && touch /tmp/steamcmd_ok && break; \
        echo "steamcmd attempt $i failed, retrying in 15s..."; \
        sleep 15; \
    done && test -f /tmp/steamcmd_ok

# Start fresh for the final image
FROM cm2network/steamcmd:root

# Set environment variables
ENV STEAM_APPID=896660
ENV VALHEIM_DIR="/home/steam/valheim"
ENV VALHEIM_SAVE_PATH="/valheimdata"

# Create necessary directories with correct structure
RUN mkdir -p ${VALHEIM_DIR} && \
    mkdir -p ${VALHEIM_SAVE_PATH}/worlds_local && \
    mkdir -p ${VALHEIM_SAVE_PATH}/worlds && \
    mkdir -p ${VALHEIM_SAVE_PATH}/characters && \
    mkdir -p ${VALHEIM_SAVE_PATH}/saves && \
    mkdir -p /home/steam/.steam/sdk64 && \
    chown -R steam:steam /home/steam && \
    chown -R steam:steam ${VALHEIM_SAVE_PATH}

# Copy server files from builder stage
COPY --from=steamcmd ${VALHEIM_DIR} ${VALHEIM_DIR}

# Copy entrypoint script
COPY entrypoint.sh /home/steam/entrypoint.sh

# Switch to steam user
USER steam
WORKDIR ${VALHEIM_DIR}

# Set up Steam libraries
RUN ln -sf /home/steam/steamcmd/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so

# Expose the required ports
EXPOSE 2456-2458/udp

# Set the entrypoint
# SERVER_NAME, WORLD_NAME, SERVER_PASS, and SERVER_PUBLIC must be provided via environment variables
# SERVER_CROSSPLAY (optional) enables the -crossplay flag when set to "1"
ENTRYPOINT ["sh", "/home/steam/entrypoint.sh"]

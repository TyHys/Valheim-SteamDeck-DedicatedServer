FROM cm2network/steamcmd:root

# Set environment variables
ENV STEAM_APPID=896660
ENV VALHEIM_DIR="/home/steam/valheim"
ENV CACHE_DIR="/home/steam/valheim-cache"
ENV SERVER_NAME="My Server"
ENV WORLD_NAME="My World"
ENV SERVER_PASS="your_password"
ENV SERVER_PUBLIC="true"

# Create directories and set permissions
RUN mkdir -p ${VALHEIM_DIR} ${CACHE_DIR} && \
    chown -R steam:steam /home/steam

# Switch to steam user
USER steam
WORKDIR /home/steam

# Install Valheim Dedicated Server
RUN mkdir -p ~/.steam && \
    if [ ! -f "${CACHE_DIR}/valheim_server_installed" ]; then \
        /home/steam/steamcmd/steamcmd.sh +force_install_dir ${VALHEIM_DIR} +login anonymous +app_update ${STEAM_APPID} validate +quit && \
        cp -r ${VALHEIM_DIR}/* ${CACHE_DIR}/ && \
        touch ${CACHE_DIR}/valheim_server_installed; \
    else \
        cp -r ${CACHE_DIR}/* ${VALHEIM_DIR}/; \
    fi

# Create necessary directories for world data
RUN mkdir -p ~/.config/unity3d/IronGate/Valheim/worlds_local && \
    mkdir -p ~/.config/unity3d/IronGate/Valheim/worlds

# Set up Steam libraries
RUN mkdir -p ~/.steam/sdk64 && \
    [ -e ~/.steam/sdk64/steamclient.so ] || ln -s /home/steam/steamcmd/linux64/steamclient.so ~/.steam/sdk64/steamclient.so

# Switch back to root for final setup
USER root
RUN chown -R steam:steam /home/steam

# Switch back to steam user for running the server
USER steam

# Set the working directory
WORKDIR ${VALHEIM_DIR}

# Expose the required ports
EXPOSE 2456-2458/udp

# Set the entrypoint
ENTRYPOINT ./valheim_server.x86_64 -name "$SERVER_NAME" -world "$WORLD_NAME" -password "$SERVER_PASS" -public "$SERVER_PUBLIC"

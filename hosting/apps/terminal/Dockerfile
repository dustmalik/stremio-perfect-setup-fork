FROM node:20-slim

# Install system tools needed by main.sh and terminal operations
# Include build-essential temporarily for WeTTY native module compilation
RUN apt-get update && apt-get install -y \
    bash \
    openssh-client \
    curl \
    git \
    openssl \
    whiptail \
    python3 \
    build-essential \
    && npm install -g wetty \
    && apt-get remove -y build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for terminal sessions
RUN useradd -m -s /bin/bash terminal

# Copy Node server dependencies and code
COPY --chown=root:root apps/terminal/package.json /app/
WORKDIR /app
RUN npm install --production

COPY --chown=root:root apps/terminal/server.js /app/

# Copy per-session wrapper script
COPY --chown=root:root apps/terminal/run-session.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/run-session.sh

EXPOSE 3000

USER terminal

CMD ["npm", "start"]

#!/bin/bash
cd "$(dirname "$0")"

# Check if required ports are available before starting
PORTS=(5520 25565 19132 7777 7778 27015 7779 7780)
BLOCKED=()

for port in "${PORTS[@]}"; do
    if ss -tlnu 2>/dev/null | grep -q ":${port} "; then
        BLOCKED+=("$port")
    fi
done

if [ ${#BLOCKED[@]} -gt 0 ]; then
    echo "ERROR: The following ports are already in use: ${BLOCKED[*]}"
    echo "Free them before starting, or change the port mappings in docker-compose.yml."
    read -p "Press Enter to exit..."
    exit 1
fi

docker compose up -d
read -p "Press Enter to exit..."

# realmd/Dockerfile
FROM ubuntu:25.04

RUN apt-get update && apt-get install -y \
    libace-dev \
    libmariadb3 \
    libssl3 \
    libz-dev \
    libzstd1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/realmd

COPY realmd .
COPY realmd.conf .

RUN chmod +x realmd

EXPOSE 3724

CMD ["./realmd", "-c", "realmd.conf"]

# mangosd/Dockerfile
FROM ubuntu:25.04

RUN apt-get update && apt-get install -y \
    libace-dev \
    libmariadb3 \
    libssl3 \
    libz-dev \
    libzstd1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/mangosd

COPY mangosd .
COPY mangosd.conf .

RUN chmod +x mangosd

# World server port and optional SOAP port
EXPOSE 8085
EXPOSE 7878

CMD ["./mangosd", "-c", "mangosd.conf"]

FROM alpine:3.20
RUN apk add --no-cache curl jq ca-certificates tzdata python3

WORKDIR /app

COPY hetzner-ddns.sh /app/hetzner-ddns.sh
COPY start.sh /app/start.sh

RUN chmod +x /app/hetzner-ddns.sh /app/start.sh

ENTRYPOINT ["/app/start.sh"]

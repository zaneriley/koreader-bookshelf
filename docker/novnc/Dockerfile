FROM koreader/koappimage:latest

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        fluxbox \
        imagemagick \
        novnc \
        websockify \
        x11-apps \
        x11vnc \
        xdotool \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

COPY docker/novnc/start-koreader-novnc.sh /usr/local/bin/start-koreader-novnc.sh
RUN chmod +x /usr/local/bin/start-koreader-novnc.sh

EXPOSE 6080

ENTRYPOINT ["/usr/local/bin/start-koreader-novnc.sh"]

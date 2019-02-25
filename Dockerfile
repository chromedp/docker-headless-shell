FROM blitznote/debase:18.04

RUN \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && apt-get update -y \
    && apt-get install -y libnspr4 libnss3 libexpat1 libfontconfig1 libuuid1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 

ARG VER

COPY \
    out/$VER/headless-shell/headless-shell \
    out/$VER/headless-shell/.stamp \
    out/$VER/headless-shell/swiftshader \
    /headless-shell/

EXPOSE 9222

ENTRYPOINT [ "/headless-shell/headless-shell", "--no-sandbox", "--remote-debugging-address=0.0.0.0", "--remote-debugging-port=9222" ]

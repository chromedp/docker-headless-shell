FROM debian:bullseye-slim
ARG VERSION
RUN \
    apt-get update -y \
    && apt-get install -y libnspr4 libnss3 libexpat1 libfontconfig1 libuuid1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
COPY \
    out/$VERSION/headless-shell/headless-shell \
    out/$VERSION/headless-shell/.stamp \
    /headless-shell/
COPY \
    out/$VERSION/headless-shell/swiftshader \
    /headless-shell/swiftshader
EXPOSE 9222
ENV PATH /headless-shell:$PATH
ENTRYPOINT [ "/headless-shell/headless-shell", "--no-sandbox", "--remote-debugging-address=0.0.0.0", "--remote-debugging-port=9222" ]

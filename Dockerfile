FROM blitznote/debase:18.04

RUN \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && perl -pi -e 's/archive.ubuntu.com/us.archive.ubuntu.com/' /etc/apt/sources.list \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends \
        libnspr4 libnss3 libexpat1 libfontconfig1 libuuid1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 

ARG VER

ADD out/headless-shell-$VER.tar.bz2 /

ENV PATH="/headless-shell:${PATH}"

EXPOSE 9222

ENTRYPOINT [ "/headless-shell/headless-shell", "--headless", "--no-sandbox", "--remote-debugging-address=0.0.0.0", "--remote-debugging-port=9222" ]

FROM blitznote/debase:17.10

RUN \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && perl -pi -e 's/archive.ubuntu.com/us.archive.ubuntu.com/' /etc/apt/sources.list \
    && apt-get update -y

RUN \
    apt-get install -y \
    libnspr4 libnss3 libexpat1 libfontconfig1

RUN \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 

ARG VER

ADD out/headless_shell-$VER.tar.bz2 /headless_shell/

EXPOSE 9222

ENTRYPOINT [ "/headless_shell/headless_shell", "--headless", "--no-sandbox", "--remote-debugging-address=0.0.0.0", "--remote-debugging-port=9222" ]

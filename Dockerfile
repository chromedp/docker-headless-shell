FROM blitznote/debootstrap-amd64:16.04 

RUN \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && perl -pi -e 's/archive.ubuntu.com/us.archive.ubuntu.com/' /etc/apt/sources.list \
    && apt-get update -y \
    && apt-get upgrade -y
    
RUN \
    apt-get install -y \
    libnspr4 libnspr4-0d libnspr4 libnss3 libnss3-1d \
    libexpat1 libfontconfig1

ADD https://storage.googleapis.com/docker-chrome-headless/headless_shell.tar.bz2 /tmp/

RUN \
    mkdir -p /headless_shell \
    && cd /headless_shell/ \
    && tar -jxvf /tmp/headless_shell.tar.bz2

RUN \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 

EXPOSE 9222

ENTRYPOINT [ "/headless_shell/headless_shell", "--headless", "--no-sandbox", "--remote-debugging-address=0.0.0.0", "--remote-debugging-port=9222" ]

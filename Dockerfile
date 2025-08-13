FROM docker.io/library/debian:trixie-slim
ARG VERSION
RUN \
    apt-get update -y \
    && apt-get install --no-install-recommends -y libnspr4 libnss3 libexpat1 libfontconfig1 libuuid1 socat \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
COPY \
    out/$VERSION/headless-shell/headless-shell \
    out/$VERSION/headless-shell/.stamp \
    out/$VERSION/headless-shell/libEGL.so \
    out/$VERSION/headless-shell/libGLESv2.so \
    out/$VERSION/headless-shell/libvk_swiftshader.so \
    out/$VERSION/headless-shell/libvulkan.so.1 \
    out/$VERSION/headless-shell/vk_swiftshader_icd.json \
    /headless-shell/
COPY run.sh /headless-shell/
EXPOSE 9222
EXPOSE 9223
ENV LANG en-US.UTF-8
ENV PATH /headless-shell:$PATH
ENTRYPOINT [ "/headless-shell/run.sh" ]

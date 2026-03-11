FROM docker.io/library/debian:trixie-slim
ARG VERSION
RUN \
  apt-get update -y \
  && apt-get install --no-install-recommends -y libnspr4 libnss3 libexpat1 libfontconfig1 libuuid1 socat \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
COPY \
  out/$VERSION/headless-shell/ /headless-shell/
COPY run.sh /headless-shell/
EXPOSE 9222
EXPOSE 9223
ENV LANG en-US.UTF-8
ENV PATH /headless-shell:$PATH
ENTRYPOINT [ "/headless-shell/run.sh" ]

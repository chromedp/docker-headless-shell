FROM alpine:edge

ARG VER

ENV GLIBC_VERSION=2.27-r0

EXPOSE 9222

RUN \
  apk add \
    --no-cache ca-certificates nss expat libuuid patchelf \
  && wget -q -O \
    /etc/apk/keys/sgerrand.rsa.pub \
    https://raw.githubusercontent.com/sgerrand/alpine-pkg-glibc/master/sgerrand.rsa.pub \
  && wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk \
  && wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk \
  && wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-i18n-${GLIBC_VERSION}.apk \
  && apk add glibc-${GLIBC_VERSION}.apk glibc-bin-${GLIBC_VERSION}.apk glibc-i18n-${GLIBC_VERSION}.apk \
  && rm glibc-${GLIBC_VERSION}.apk glibc-bin-${GLIBC_VERSION}.apk glibc-i18n-${GLIBC_VERSION}.apk

RUN /usr/glibc-compat/bin/localedef -i en_US -f UTF-8 en_US.UTF-8

ADD out/headless-shell-$VER.tar.bz2 /
RUN chown -R root:root /headless-shell

#CMD ./headless-shell --headless --remote-debugging-port=9222

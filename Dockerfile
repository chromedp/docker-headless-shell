FROM alpine:edge

EXPOSE 9222

COPY kenneth.shaw@knq.io-5b9e5e63.rsa.pub /etc/apk/keys/

RUN \
  echo "https://apk.brank.as/edge" | tee -a /etc/apk/repositories \
  && apk update \
  && apk add --no-cache headless-shell \
  && rm -rf /tmp/* /var/tmp/* /var/cache/apk/* 

ENTRYPOINT [ "headless-shell", "--headless", "--no-sandbox", "--remote-debugging-port=9222"]

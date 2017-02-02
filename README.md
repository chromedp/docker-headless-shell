# About docker-chrome-headless

This repository contains the sources for the Docker `knqz/chrome-headless`
container.

It contains the `headless_shell` Chrome app that has a custom user-agent. This
image was made to run the unit tests for the Go [`chromedp`](https://github.com/knq/chromedp)
package. It is as stripped to the smallest possible install for Chrome.

## Running

```sh
docker run -d -p 9222:9222 --rm --name chrome-headless knqz/chrome-headless
```

## Building Manually

You will need to build the `headless_shell` [manually](https://chromium.googlesource.com/chromium/src/+/lkgr/headless/README.md).

You then need to run the [`package.sh`](package.sh) script to package it prior
to building the image.

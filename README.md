# About headless-shell

The [headless-shell][headless-shell] project provides a multi-arch container
image, [`docker.io/chromedp/headless-shell`][docker-headless-shell], containing
Chrome's `headless-shell` -- a slimmed down version of Chrome that is useful
for driving, profiling, or testing web pages.

This image has been created for the Go [`chromedp` package][chromedp], which
provides a simple and easy to use API for driving browsers compatible with the
[Chrome Debugging Protocol][devtools-protocol], but can be used with library or
application that supports the Chrome Debugging Protocol.

The version of `headless-shell` contained in the [`docker.io/chromedp/headless-shell`][docker-headless-shell]
has been modified from the original Chromium source tree, to report the same
user agent as Chrome, and has had other minor modifications made to it in order
to make it better suited for use in an embedded context.

## Tags and Versions

Multi-arch images for Chrome's `stable`, `beta`, and `dev` channels are pushed
daily to the [`docker.io/chromedp/headless-shell`][docker-headless-shell]
repository.

The image can be used via the `stable`, `beta`, or `dev` floating tags, or via
a specific version tag:

```sh
# pull latest stable
$ podman pull docker.io/chromedp/headless-shell:latest

# pull specific version
$ podman pull docker.io/chromedp/headless-shell:123.0.6312.86

# pull beta
$ podman pull docker.io/chromedp/headless-shell:beta

# pull dev
$ podman pull docker.io/chromedp/headless-shell:dev
```

## Running

The `headless-shell` container can be used in the usual way:

```sh
# run
$ podman run -d -p 9222:9222 --rm --name headless-shell docker.io/chromedp/headless-shell

# if headless-shell is crashing with a BUS_ADRERR error, pass a larger shm-size:
$ podman run -d -p 9222:9222 --rm --name headless-shell --shm-size 2G docker.io/chromedp/headless-shell

# run as unprivileged user
# get seccomp profile from https://raw.githubusercontent.com/jfrazelle/dotfiles/master/etc/docker/seccomp/chrome.json
$ podman run -d -p 9222:9222 --user nobody --security-opt seccomp=chrome.json --entrypoint '/headless-shell/headless-shell' docker.io/chromedp/headless-shell --remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --disable-gpu --headless
```

## Zombie processes

When using `docker.io/chromedp/headless-shell` (either directly or as a base
image), you could experience zombie processes problem. To reap zombie
processes, use `podman run`'s `--init` arg:

```sh
$ podman run -d -p <PORT>:<PORT> --name <your-program> --init <your-image>
```

If running Docker older than 1.13.0, use [`dumb-init`][dumb-init] or
[`tini`][tini] on your `Dockerfile`'s `ENTRYPOINT`

```Dockerfile
FROM docker.io/chromedp/headless-shell:latest
...
# Install dumb-init or tini
RUN apt install dumb-init
# or RUN apt install tini
...
ENTRYPOINT ["dumb-init", "--"]
# or ENTRYPOINT ["tini", "--"]
CMD ["/path/to/your/program"]
```

[headless-shell]: https://github.com/chromedp/docker-headless-shell
[docker-headless-shell]: https://hub.docker.com/r/chromedp/headless-shell/tags
[devtools-protocol]: https://chromedevtools.github.io/devtools-protocol/
[chromedp]: https://github.com/chromedp/chromedp
[building-linux]: https://chromium.googlesource.com/chromium/src/+/main/docs/linux/build_instructions.md
[building-headless]: https://chromium.googlesource.com/chromium/src/+/main/headless/README.md
[dumb-init]: https://github.com/Yelp/dumb-init
[tini]: https://github.com/krallin/tini

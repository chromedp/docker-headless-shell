# About headless-shell

The [headless-shell][headless-shell] project provides a container image,
[`docker.io/chromedp/headless-shell`][docker-headless-shell], containing a
pre-built version of Chrome's `headless-shell` -- a slimmed down version of
Chrome that is useful for driving, profiling, or testing web pages.

Notably, this Docker image has been created expressly for the Go [`chromedp`
package][chromedp], which provides a simple and easy to use API for driving
browsers compatible with the [Chrome Debugging Protocol][devtools-protocol].

The version of `headless-shell` contained in the [`docker.io/chromedp/headless-shell`][docker-headless-shell]
has been modified from the original Chromium source tree, to report the same
user agent as Chrome, and has had other minor modifications made to it in order
to make it better suited for use in an embedded context.

## Running

You can use this container in the usual way:

```sh
# pull latest stable version
$ podman pull docker.io/chromedp/headless-shell:latest

# pull specific tagged version of headless-shell
$ podman pull docker.io/chromedp/headless-shell:74.0.3717.1

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

```bash
podman run -d -p <PORT>:<PORT> --name <your-program> --init <your-image>
```

If running Docker older than 1.13.0, use [`dumb-init`][dumb-init] or
[`tini`][tini] on your `Dockerfile`'s `ENTRYPOINT`

```dockerfile
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

## Building and Packaging

The following contains instructions for building and packaging the
`docker.io/chromedp/headless-shell` Docker image manually.

### Setup and Building

If you'd like to build this image yourself, locally, you will need to build
`headless-shell` manually from the Chromium source.

Please see the following for instructions on building Chromium and
`headless-shell` on Linux:

- [Checking out and building Chromium on Linux][building-linux]
- [Building Headless Chromium][building-headless]

Before proceeding, please ensure you have fully completed the above, have
manually built `headless-shell` at least once, and that your Chromium source
tree is up-to-date.

### Building

After you are able to successfully build `headless-shell` directly from the
Chromium source tree, you can simply run [`build-image.sh`](build-image.sh):

```sh
# build headless-shell
$ ./build-headless-shell.sh -v 74.0.3717.1

# build image (uses $PWD/out/headless-shell-$VER-{amd64,arm64}.tar.bz2)
$ ./build-image.sh -v 74.0.3717.1
```

[headless-shell]: https://github.com/chromedp/docker-headless-shell
[docker-headless-shell]: https://hub.docker.com/r/chromedp/headless-shell/
[devtools-protocol]: https://chromedevtools.github.io/devtools-protocol/
[chromedp]: https://github.com/chromedp/chromedp
[building-linux]: https://chromium.googlesource.com/chromium/src/+/main/docs/linux/build_instructions.md
[building-headless]: https://chromium.googlesource.com/chromium/src/+/main/headless/README.md
[dumb-init]: https://github.com/Yelp/dumb-init
[tini]: https://github.com/krallin/tini

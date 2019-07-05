# About headless-shell

The [headless-shell][headless-shell] project provides a Docker image,
[`chromedp/headless-shell`][docker-headless-shell], containing a pre-built
version of Chrome's `headless-shell` -- a slimmed down version of Chrome that
is useful for driving, profiling, or testing web pages.

Notably, this Docker image has been created expressly for the Go [`chromedp`
package][chromedp], which provides a simple and easy to use API for driving
browsers compatible with the [Chrome Debugging Protocol][devtools-protocol].

The version of `headless-shell` contained in this Docker image has been
modified from the original Chromium source tree, to report the same user agent
as Chrome, and has had other minor modifications made to it in order make it
better suited for use in an embedded context.

## Running

You can use this Docker image in the usual way:

```sh
# pull latest version of headless-shell
$ docker pull chromedp/headless-shell:latest

# pull specific tagged version of headless-shell
$ docker pull chromedp/headless-shell:74.0.3717.1

# run
$ docker run -d -p 9222:9222 --rm --name headless-shell chromedp/headless-shell

# if headless-shell is crashing with a BUS_ADRERR error, pass a larger shm-size:
$ docker run -d -p 9222:9222 --rm --name headless-shell --shm-size 2G chromedp/headless-shell

# run as unprivileged user
# get seccomp profile from https://raw.githubusercontent.com/jfrazelle/dotfiles/master/etc/docker/seccomp/chrome.json
$ docker run -d -p 9222:9222 --user nobody --security-opt seccomp=chrome.json --entrypoint '/headless-shell/headless-shell' chromedp/headless-shell --remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --disable-gpu --headless
```

## Building and Packaging

The following contains instructions for building and packaging the
`chromedp/headless-shell` Docker image manually.

### Setup and Building

If you'd like to build this image yourself, locally, you will need to build
`headless-shell` manually from the Chromium source. As such you will need to
setup Chromium's `depot_tools`, your build environment, and a full checkout of
the Chromium source tree and its related dependencies.

Please see the following for instructions on building Chromium and
`headless-shell` on Linux:

* [Checking out and building Chromium on Linux][building-linux]
* [Building Headless Chromium][building-headless]

Before proceeding, please ensure you have fully completed the above, have
manually built `headless-shell` at least once, and that your Chromium source
tree is up-to-date.

### Building

After you are able to successfully build `headless-shell` directly from the
Chromium source tree, you can simply run [`build-docker.sh`](build-docker.sh):

```sh
# build headless-shell
$ ./build-headless-shell.sh /path/to/chromium/src 74.0.3717.1

# build docker image (uses $PWD/out/headless-shell-$VER.tar.bz2)
$ ./build-docker.sh 74.0.3717.1
```

[headless-shell]: https://github.com/chromedp/docker-headless-shell
[docker-headless-shell]: https://hub.docker.com/r/chromedp/headless-shell/
[devtools-protocol]: https://chromedevtools.github.io/devtools-protocol/
[chromedp]: https://github.com/chromedp/chromedp
[building-linux]: https://chromium.googlesource.com/chromium/src/+/master/docs/linux_build_instructions.md
[building-headless]: https://chromium.googlesource.com/chromium/src/+/master/headless/README.md

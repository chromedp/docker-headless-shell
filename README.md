# About chrome-headless

The [chrome-headless](https://github.com/knq/chrome-headless) project provides
a Docker image, [`knqz/chrome-headless`](https://hub.docker.com/r/knqz/chrome-headless/),
containing a pre-built version of Chrome's `headless_shell` -- a slimmed
down version of Chrome that is useful for driving, profiling, or testing web
pages.

Notably, this Docker image has been created expressly for the Go
[chromedp](https://github.com/knq/chromedp) package, which provides a simple
and easy to use API for driving browsers compatible with the [Chrome Debugging
Protocol](https://developer.chrome.com/devtools/docs/debugger-protocol).

The version of `headless_shell` contained in this Docker image has been
[modified from the original](patches/) Chromium source tree, to report the same
user agent as Chrome, and has had other minor modifications made to it in order
make it better suited for use in an embedded context.

## Running

You can use this Docker image in the usual way:

```sh
# updated to latest version of chrome-headless
docker pull knqz/chrome-headless

# update to specific tagged version of chrome-headless
docker pull knqz/chrome-headless:58.0.3005.6

# run
docker run -d -p 9222:9222 --rm --name chrome-headless knqz/chrome-headless
```

## Building and Packaging

The following contains instructions for building and packaging the
`knqz/chrome-headless` Docker image manually.

### Setup and Building Chromium

You will need to build `headless_shell` manually from the Chromium source, as
such you will need to setup Chromium's `depot_tools`, your build environment,
and checkout the Chromium source tree and its related dependencies.

Please see the following for instructions on building Chromium and
`headless_shell` on Linux:

* [Checking out and building Chromium on Linux](https://chromium.googlesource.com/chromium/src/+/master/docs/linux_build_instructions.md)
* [Building Headless Chromium](https://chromium.googlesource.com/chromium/src/+/master/headless/README.md)

Before proceeding, please ensure you have fully completed the above, have
manually built `headless_shell` at least once, and that your Chromium source
tree is up-to-date.

### Building

After you are able to successfully build `headless_shell` directly from the
Chromium source tree, you can simply run `build.sh`

```sh
# build latest tag
$ ./build.sh /path/to/chromium/src

# build specific tag
$ ./build.sh -tag 58.0.3005.6 /path/to/chromium/src
```

### Packaging

After you have applied the necessary patches, and have manually built
`headless_shell` you need to run the [`package.sh`](package.sh) script in order
to package `headless_shell` for use with Docker.

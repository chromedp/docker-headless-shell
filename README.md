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
$ podman run -d -p 9222:9222 --user nobody --security-opt seccomp=chrome.json --entrypoint '/headless-shell/headless-shell' docker.io/chromedp/headless-shell --remote-debugging-address=0.0.0.0 --remote-debugging-port=9222 --disable-gpu --enable-unsafe-swiftshader --headless
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

## Building

`headless-shell` is built nightly on an Arch Linux host by the scripts in this
repository (see [Chromium's Linux build instructions][building-linux] and the
[headless README][building-headless]). The build runs directly on the host, and
only the resulting binaries are packaged into the container image.

### Host packages

Install the following with `yay -S`:

```sh
$ yay -S --needed \
    base-devel git git-lfs python perl curl jq go bzip2 \
    aarch64-linux-gnu-binutils gperf \
    buildah podman qemu-user-static qemu-user-static-binfmt
```

- `git`, `git-lfs`, `python` and `perl` are used by the scripts, `gclient` and
  the Chromium build. `git-lfs` is required: Chromium's `third_party/litert`
  contains Git LFS files, and `gclient sync` fails without it
- `base-devel` provides the build tools used by the scripts and Chromium's
  build (`binutils`, `bison`, `flex`, `patch`, `file`, and so on). `strip` from
  `binutils` is used on the amd64 binary
- `curl`, `jq` and `bzip2` are used by the scripts to verify and package the
  build
- `aarch64-linux-gnu-binutils` provides `aarch64-linux-gnu-strip`, used on the
  arm64 binary
- `gperf`, along with `bison` and `flex`, is a build tool named in Chromium's
  `build/install-build-deps.py`. The remaining packages there are for
  packaging, tests and distro libraries, and are not needed, as Chromium's
  toolchain and sysroots are downloaded by `gclient`
- `buildah`, `podman`, `qemu-user-static` and `qemu-user-static-binfmt` are
  used to build and push the multi-arch container images
- `go` is needed to install `verhist`, which is not packaged:

  ```sh
  $ go install github.com/chromedp/verhist/cmd/verhist@latest
  ```

  and it must be on the `PATH` of the user running the build

### Running the build

```sh
# enable lingering and the timers
$ sudo loginctl enable-linger $USER
$ ./install.sh
$ systemctl enable --now --user headless-shell.timer

# run a build by hand, see all options with --help
$ ./build.sh --help
$ ./build.sh --channel stable --target amd64

# follow a build
$ journalctl --user -fu headless-shell.service
```

Pushing requires a registry token in `~/.config/headless-shell/token`.

[headless-shell]: https://github.com/chromedp/docker-headless-shell
[docker-headless-shell]: https://hub.docker.com/r/chromedp/headless-shell/tags
[devtools-protocol]: https://chromedevtools.github.io/devtools-protocol/
[chromedp]: https://github.com/chromedp/chromedp
[building-linux]: https://chromium.googlesource.com/chromium/src/+/main/docs/linux/build_instructions.md
[building-headless]: https://chromium.googlesource.com/chromium/src/+/main/headless/README.md
[dumb-init]: https://github.com/Yelp/dumb-init
[tini]: https://github.com/krallin/tini

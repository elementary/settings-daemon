# Settings Daemon

## Building and Installation

You'll need the following dependencies:
* glib-2.0
* gobject-2.0
* libaccountsservice-dev
* libdbus-1-dev
* libfwupd-dev
* libgeoclue-2-dev
* libgranite-dev
* libpackagekit-glib2-dev
* meson
* valac

Run `meson build` to configure the build environment. Change to the build directory and run `ninja` to build

```bash
meson build --prefix=/usr
cd build
ninja
```

To install, use `ninja install`, then execute with `io.elementary.settings-daemon`

```bash
ninja install
io.elementary.settings-daemon
```

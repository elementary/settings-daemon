sources = files(
    'Application.vala',
)

executable(
    meson.project_name() + '.check-for-firmware-updates',
    sources,
    dependencies: [
        config_dep,
        fwupd,
        gio_dep,
        glib_dep,
    ],
    install: true,
    install_dir: libexecdir,
)

install_data(
    meson.project_name() + '.check-for-firmware-updates.service',
    install_dir: systemd_system_unit_dir
)

install_data(
    meson.project_name() + '.check-for-firmware-updates.timer',
    install_dir: systemd_system_unit_dir
)

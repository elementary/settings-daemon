install_data(
    'autostart.desktop',
    install_dir: datadir / 'applications',
    rename: meson.project_name() + '.desktop'
)

install_symlink(
    meson.project_name() + '.desktop',
    install_dir: get_option('sysconfdir') / 'xdg' / 'autostart',
    pointing_to: datadir / 'applications' / meson.project_name() + '.desktop'
)

dbus_dep = dependency('dbus-1')
dbus_interfaces_dir = dbus_dep.get_pkgconfig_variable('interfaces_dir', define_variable: ['datadir', datadir])

install_data(
    'io.elementary.SettingsDaemon.AccountsService.xml',
    install_dir: dbus_interfaces_dir
)

act_dep = dependency('accountsservice')
act_interfacesdir = act_dep.get_pkgconfig_variable('interfacesdir', define_variable: ['datadir', datadir], default: datadir /'accountsservice' / 'interfaces')

meson.add_install_script(
    symlink,
    join_paths(dbus_interfaces_dir, 'io.elementary.SettingsDaemon.AccountsService.xml'),
    join_paths(act_interfacesdir, 'io.elementary.SettingsDaemon.AccountsService.xml'),
)

install_data(
    'io.elementary.settings-daemon.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas')
)

i18n.merge_file(
    input: 'settings-daemon.metainfo.xml.in',
    output: meson.project_name() + '.metainfo.xml',
    po_dir: meson.project_source_root() / 'po',
    type: 'xml',
    install: true,
    install_dir: get_option('datadir') / 'metainfo',
)

systemd = dependency('systemd')
systemd_system_unit_dir = systemd.get_pkgconfig_variable('systemdsystemunitdir')

install_data(
    meson.project_name() + '.check-for-firmware-updates.service',
    install_dir: systemd_system_unit_dir
)

install_data(
    meson.project_name() + '.check-for-firmware-updates.timer',
    install_dir: systemd_system_unit_dir
)

icon_sizes = ['24', '32', '48', '64', '128']

foreach i : icon_sizes
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', i + 'x' + i, 'apps'),
        rename: meson.project_name() + '.svg'
    )
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', i + 'x' + i + '@2', 'apps'),
        rename: meson.project_name() + '.svg'
    )
endforeach

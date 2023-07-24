install_data(
    'autostart.desktop',
    install_dir: datadir / 'applications',
    rename: meson.project_name() + '.desktop'
)

install_symlink(
    meson.project_name() + '.desktop',
    install_dir: get_option('sysconfdir') / 'xdg' / 'autostart',
    pointing_to: get_option('prefix') / get_option('datadir') / 'applications' / meson.project_name() + '.desktop'
)

dbus_dep = dependency('dbus-1')
dbus_interfaces_dir = dbus_dep.get_variable('interfaces_dir', pkgconfig_define: ['datadir', datadir])

install_data(
    'io.elementary.SettingsDaemon.AccountsService.xml',
    install_dir: dbus_interfaces_dir
)

act_dep = dependency('accountsservice')
act_interfacesdir = act_dep.get_variable('interfacesdir', pkgconfig_define: ['datadir', datadir], default_value: datadir /'accountsservice' / 'interfaces')

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
systemd_system_unit_dir = systemd.get_variable('systemdsystemunitdir')

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
        install_dir: get_option('datadir') / 'icons' / 'hicolor' / i + 'x' + i / 'apps',
        rename: meson.project_name() + '.svg'
    )
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: get_option('datadir') / 'icons' / 'hicolor' / i + 'x' + i + '@2' / 'apps',
        rename: meson.project_name() + '.svg'
    )
endforeach

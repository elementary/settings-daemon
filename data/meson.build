install_data(
    'autostart.desktop',
    install_dir: datadir / 'applications',
    rename: meson.project_name() + '.desktop'
)

fs = import('fs')
meson.add_install_script(
    symlink,
    datadir / 'applications' / meson.project_name() + '.desktop',
    (fs.is_absolute(sysconfdir) ? sysconfdir : (prefix / sysconfdir)) / 'xdg' / 'autostart' / meson.project_name() + '.desktop',
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
    dbus_interfaces_dir / 'io.elementary.SettingsDaemon.AccountsService.xml',
    act_interfacesdir / 'io.elementary.SettingsDaemon.AccountsService.xml',
)

install_data(
    'io.elementary.settings-daemon.gschema.xml',
    install_dir: datadir / 'glib-2.0' / 'schemas'
)

i18n.merge_file(
    input: 'settings-daemon.metainfo.xml.in',
    output: meson.project_name() + '.metainfo.xml',
    po_dir: meson.project_source_root() / 'po',
    type: 'xml',
    install: true,
    install_dir: get_option('datadir') / 'metainfo',
)

busctl_path = get_option('busctlpath')
systemd_system_unit_dir = get_option('systemdsystemunitdir')

if systemd_system_unit_dir != 'no'
    systemd = dependency('systemd')
    if systemd_system_unit_dir == ''
        systemd_system_unit_dir = systemd.get_variable('systemdsystemunitdir', pkgconfig_define: ['rootprefix', prefix])
    endif
    if busctl_path == ''
        busctl_path = systemd.get_variable('prefix') / 'bin' / 'busctl'
    endif

    service_config = configuration_data()
    service_config.set('busctl_path', busctl_path)

    configure_file(
        input: meson.project_name() + '.check-for-firmware-updates.service.in',
        output: meson.project_name() + '.check-for-firmware-updates.service',
        configuration: service_config,
        install_dir: systemd_system_unit_dir
    )

    install_data(
        meson.project_name() + '.check-for-firmware-updates.timer',
        install_dir: systemd_system_unit_dir
    )
endif

configure_file(
    input: 'settings-daemon.policy.in',
    output: 'io.elementary.settings-daemon.policy',
    configuration: conf_data,
    install_dir: polkit_dep.get_pkgconfig_variable('policydir', define_variable: ['prefix', prefix])
)

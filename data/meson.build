install_data(
    'autostart.desktop',
    install_dir: join_paths(get_option('sysconfdir'), 'xdg', 'autostart'),
    rename: meson.project_name() + '.desktop'
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
    input: 'settings-daemon.appdata.xml.in',
    output: meson.project_name() + '.appdata.xml',
    po_dir: join_paths(meson.source_root(), 'po'),
    type: 'xml',
    install: true,
    install_dir: join_paths(get_option('datadir'), 'metainfo'),
)

i18n.merge_file(
    input: meson.project_name() + '.policy.in',
    output: meson.project_name() + '.policy',
    po_dir: join_paths(meson.source_root (), 'po'),
    install_dir: join_paths(get_option('datadir'), 'polkit-1', 'actions'),
    install: true
)

install_subdir(
    'system-upgrades',
    install_dir: pkgdatadir
)

install_data(
    meson.project_name() + '.system-upgrade.helper',
    install_mode: 'r-xr--r--',
    install_dir: pkgdatadir
)

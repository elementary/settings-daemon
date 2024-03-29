libexec_dir = prefix / get_option ('libexecdir')

portal_sources = files(
    'Main.vala',
    'Settings.vala',
)

executable(
    'io.elementary.settings-daemon.xdg-desktop-portal',
    portal_sources,
    dependencies: [
        config_dep,
        glib_dep,
        gio_dep,
    ],
    install: true,
    install_dir: libexec_dir,
)

portal_conf_data = configuration_data()
portal_conf_data.set('libexecdir', libexec_dir)

systemd_systemduserunitdir = get_option('systemduserunitdir')
if systemd_systemduserunitdir != 'no'

  if systemd_systemduserunitdir == ''
    systemd_dep = dependency('systemd', version: '>= 206', required: false)
    assert(systemd_dep.found(), 'systemd required but not found, please provide a valid systemd user unit dir or disable it')
    systemd_systemduserunitdir = systemd_dep.get_variable('systemduserunitdir', pkgconfig_define: ['prefix', prefix])
  endif

  configure_file(
      input: 'io.elementary.settings-daemon.xdg-desktop-portal.service.in',
      output: '@BASENAME@',
      configuration: portal_conf_data,
      install: true,
      install_dir: systemd_systemduserunitdir
  )
endif

install_data(
    'io.elementary.settings-daemon.portal',
    install_dir: datadir / 'xdg-desktop-portal' / 'portals'
)

configure_file(
    input: 'org.freedesktop.impl.portal.desktop.elementary.settings-daemon.service.in',
    output: '@BASENAME@',
    configuration: portal_conf_data,
    install: true,
    install_dir: datadir / 'dbus-1' / 'services'
)

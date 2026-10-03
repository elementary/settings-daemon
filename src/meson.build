sources = files(
    'AccountsService.vala',
    'Backends/Audio.vala',
    'Backends/EchoProcessor.vala',
    'Application.vala',
    'Backends/AccentColorManager.vala',
    'Backends/ApplicationShortcuts.vala',
    'Backends/Housekeeping.vala',
    'Backends/InterfaceSettings.vala',
    'Backends/KeyboardSettings.vala',
    'Backends/MouseSettings.vala',
    'Backends/NightLightSettings.vala',
    'Backends/PowerProfilesSync.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Backends/SystemUpdate.vala',
    'DBus/DesktopIntegration.vala',
    'DBus/ShellKeyGrabber.vala',
    'Utils/PkUtils.vala',
    'Utils/SessionUtils.vala',
    'Utils/SunriseSunsetCalculator.vala',
)

args = []

if get_option('ubuntu_drivers')
    sources += files('Backends/UbuntuDrivers.vala')
    args += '--define=UBUNTU_DRIVERS'
endif

executable(
    meson.project_name(),
    sources,
    dependencies: [
        config_dep,
        pulse_dep,
        pulse_loop_dep,
        fwupd_dep,
        gio_dep,
        glib_dep,
        granite_dep,
        gdk_pixbuf_dep,
        gexiv2_dep,
        libgeoclue_dep,
        m_dep,
        pk_dep
    ],
    vala_args: args + ['--vapidir=' + meson.project_source_root() / 'vapi', '--pkg=libpulse-operation'],
    install: true,
)

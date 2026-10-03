equalizer_library = static_library(
    'speaker-equalizer-profile',
    'Backends/speaker-equalizer-profile.c',
    dependencies: [gio_dep],
)

sources = files(
    'AccountsService.vala',
    'Backends/Audio.vala',
    'Backends/SpeakerEqualizer.vala',
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
    link_with: equalizer_library,
    dependencies: [
        config_dep,
        wireplumber_dep,
        wireplumber_vapi,
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
    vala_args: args + ['--vapidir=' + meson.project_source_root() / 'vapi',
        '--vapidir=' + meson.project_build_root(), '--pkg=libpulse-operation', '--pkg=speaker-equalizer-profile'],
    install: true,
)

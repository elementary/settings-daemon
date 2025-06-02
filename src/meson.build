sources = files(
    'AccountsService.vala',
    'Application.vala',
    'Backends/AccentColorManager.vala',
    'Backends/DisplaySettings.vala',
    'Backends/Housekeeping.vala',
    'Backends/InterfaceSettings.vala',
    'Backends/KeyboardSettings.vala',
    'Backends/MouseSettings.vala',
    'Backends/NightLightSettings.vala',
    'Backends/PowerProfilesSync.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Backends/SystemUpdate.vala',
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
    vala_args: args,
    install: true,
)

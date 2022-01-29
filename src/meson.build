sources = files(
    'AccountsService.vala',
    'Application.vala',
    'SessionManager.vala',
    'Backends/Housekeeping.vala',
    'Backends/KeyboardSettings.vala',
    'Backends/MouseSettings.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Backends/SystemUpgrade.vala',
    'Utils/SunriseSunsetCalculator.vala',
    'Utils/SystemUpgradeHelper.vala',
)

executable(
    meson.project_name(),
    sources,
    dependencies: [
        config_dep,
        gio_dep,
        glib_dep,
        granite_dep,
        libgeoclue_dep,
        m_dep,
        packagekit_dep,
        polkit_dep,
        posix_dep,
    ],
    install: true,
)

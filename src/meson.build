sources = files(
    'AccountsService.vala',
    'Application.vala',
    'SessionManager.vala',
    'Backends/Housekeeping.vala',
    'Backends/KeyboardSettings.vala',
    'Backends/MouseSettings.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Utils/SunriseSunsetCalculator.vala',
)

executable(
    meson.project_name(),
    sources,
    dependencies: [
        config_dep,
        fwupd,
        gio_dep,
        glib_dep,
        granite_dep,
        libgeoclue_dep,
        m_dep,
    ],
    install: true,
)

conf_data = configuration_data()
conf_data.set('PROJECT_NAME', meson.project_name())
conf_data.set('VERSION', meson.project_version())

config_file = configure_file(
    input: 'config.vala.in',
    output: 'config.vala',
    configuration: conf_data
)

sources = files(
    'AccountsService.vala',
    'Application.vala',
    'SessionManager.vala',
    'Backends/AccentColorSettings.vala',
    'Backends/KeyboardSettings.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Utils/ColorExtractor.vala',
    'Utils/Palette.vala',
    'Utils/SunriseSunsetCalculator.vala',
)

executable(
    meson.project_name(),
    sources,
    config_file,
    dependencies: [
        gio_dep,
        glib_dep,
        granite_dep,
        libgeoclue_dep,
        gexiv2_dep,
        m_dep,
    ],
    install: true,
)

executable(
    meson.project_name() + '.demo',
    [
        'Backends/AccentColorSettings.vala',
        'Utils/ColorExtractor.vala',
        'Utils/Palette.vala',
        'Demo.vala',
    ],
    config_file,
    dependencies: [
        gio_dep,
        glib_dep,
        granite_dep,
        libgeoclue_dep,
        gexiv2_dep,
        m_dep,
    ],
    install: false,
)

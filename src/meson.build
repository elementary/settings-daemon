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
    'Backends/KeyboardSettings.vala',
    'Backends/TimeSettings.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Utils/SunriseSunsetCalculator.vala',
)

executable(
    meson.project_name(),
    sources,
    config_file,
    dependencies: [
        dependency ('gio-2.0'),
        granite_dep,
        m_dep,
        libgeoclue_dep
    ],
    install: true,
)

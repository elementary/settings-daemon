sources = files(
    'AccountsService.vala',
    'Application.vala',
    'Backends/Housekeeping.vala',
    'Backends/InterfaceSettings.vala',
    'Backends/KeyboardSettings.vala',
    'Backends/MouseSettings.vala',
    'Backends/NightLightSettings.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Backends' / 'ScheduleManager' / 'ManualSchedule.vala',
    'Backends' / 'ScheduleManager' / 'Schedule.vala',
    'Backends' / 'ScheduleManager' / 'ScheduleManager.vala',
    'Utils/SunriseSunsetCalculator.vala',
)

executable(
    meson.project_name(),
    sources,
    dependencies: [
        config_dep,
        fwupd_dep,
        gio_dep,
        glib_dep,
        granite_dep,
        libgeoclue_dep,
        m_dep,
    ],
    install: true,
)

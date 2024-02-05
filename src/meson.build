sources = files(
    'AccountsService.vala',
    'Application.vala',
    'Backends/AccentColorManager.vala',
    'Backends/Housekeeping.vala',
    'Backends/InterfaceSettings.vala',
    'Backends/KeyboardSettings.vala',
    'Backends/MouseSettings.vala',
    'Backends/NightLightSettings.vala',
    'Backends/PrefersColorSchemeSettings.vala',
    'Backends' / 'ScheduleManager' / 'DaylightSchedule.vala',
    'Backends' / 'ScheduleManager' / 'ManualSchedule.vala',
    'Backends' / 'ScheduleManager' / 'Schedule.vala',
    'Backends' / 'ScheduleManager' / 'ScheduleManager.vala',
    'Backends/SystemUpdate.vala',
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
        gdk_pixbuf_dep,
        gexiv2_dep,
        libgeoclue_dep,
        m_dep,
        pk_dep
    ],
    install: true,
)

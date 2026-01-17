project('io.elementary.settings-daemon',
    'c', 'vala',
    version: '8.4.0',
    license: 'GPL3',
    meson_version: '>=0.59.0'
)

gnome = import('gnome')

fwupd_dep = dependency('fwupd')
gio_dep = dependency ('gio-2.0')
glib_dep = dependency('glib-2.0')
granite_dep = dependency('granite', version: '>= 5.3.0')
gdk_pixbuf_dep = dependency('gdk-pixbuf-2.0')
gexiv2_dep = dependency('gexiv2')
pk_dep = dependency('packagekit-glib2')
i18n = import('i18n')
gettext_name = meson.project_name()

if fwupd_dep.version().version_compare('>=2.0.0')
    add_project_arguments('--define', 'HAS_FWUPD_2_0', language: 'vala')
endif

add_project_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(gettext_name),
    language:'c'
)

cc = meson.get_compiler('c')
m_dep = cc.find_library('m', required : false)
libgeoclue_dep = dependency ('libgeoclue-2.0')

prefix = get_option('prefix')
datadir = prefix / get_option('datadir')

conf_data = configuration_data()
conf_data.set('PROJECT_NAME', meson.project_name())
conf_data.set('VERSION', meson.project_version())
conf_data.set('GETTEXT_PACKAGE', gettext_name)
conf_data.set('LOCALEDIR', prefix / get_option('localedir'))

config_file = configure_file(
    input: 'config.vala.in',
    output: 'config.vala',
    configuration: conf_data
)

config_dep = declare_dependency(
    sources: config_file,
    include_directories: include_directories('.')
)

symlink = meson.current_source_dir () / 'meson' / 'create-symlink.sh'

subdir('data')
subdir('po')
subdir('src')
subdir('settings-portal')

gnome.post_install(
    glib_compile_schemas: true,
    update_desktop_database: true
)

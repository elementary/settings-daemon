project('io.elementary.settings-daemon',
    'c', 'vala',
    version: '1.3.0',
    license: 'GPL3',
    meson_version: '>=0.61.0'
)

fwupd_dep = dependency('fwupd')
gio_dep = dependency ('gio-2.0')
glib_dep = dependency('glib-2.0')
granite_dep = dependency('granite', version: '>= 5.3.0')
i18n = import('i18n')
gettext_name = meson.project_name()

add_project_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(gettext_name),
    language:'c'
)

# Relying on Gala translations for screenshots directory name:
gettext_package = 'gala'
add_global_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(gettext_package),
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
conf_data.set('GETTEXT_PACKAGE', gettext_package)
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

symlink = join_paths(meson.current_source_dir (), 'meson', 'create-symlink.sh')

subdir('data')
subdir('po')
subdir('src')
subdir('settings-portal')

meson.add_install_script('meson/post_install.py')

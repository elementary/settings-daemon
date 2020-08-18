project('io.elementary.settings-daemon',
    'c', 'vala',
    version: '1.0.0',
    license: 'GPL3',
)

granite_dep = dependency('granite', version: '>= 5.3.0')

prefix = get_option('prefix')
datadir = join_paths(prefix, get_option('datadir'))

symlink = join_paths(meson.current_source_dir (), 'meson', 'create-symlink.sh')

subdir('data')
subdir('src')

meson.add_install_script('meson/post_install.py')

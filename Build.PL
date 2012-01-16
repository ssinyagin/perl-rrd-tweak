use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'RRD::Tweak',
    license             => 'gpl',
    dist_author         => q{Stanislav Sinyagin <ssinyagin@k-open.com>},
    dist_version_from   => 'lib/RRD/Tweak.pm',
    build_requires => {
        'Test::More' => 0,
        'Data::Compare' => 0,
        'Data::Dumper' => 0,
        'ExtUtils::CBuilder' => 0,
        'RRDs' => 0,
    },
    requires => {
        perl => '5.8.8',
    },
    extra_linker_flags   => ['-lrrd'],
    extra_compiler_flags => ['-O0', '-g'],
    add_to_cleanup      => [ 'RRD-Tweak-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my @programs_to_install = qw(dav.pl);

WriteMakefile(
    'NAME'	=> 'HTTP::DAV',
    'VERSION_FROM' => 'DAV.pm', # finds $VERSION
    'dist'          => { COMPRESS => 'gzip -9f --best',
                         SUFFIX => '.gz' },
    'EXE_FILES'     => [ map {"bin/$_"} @programs_to_install ],
    'PREREQ_PM' => { 
        'LWP' => 5.48,      # DAV requires LWP
        'XML::DOM' => 0, # DAV requires XML::DOM
    },
);

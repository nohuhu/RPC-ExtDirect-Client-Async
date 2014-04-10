use 5.006000;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'RPC::ExtDirect::Client::Async',
    VERSION_FROM      => 'lib/RPC/ExtDirect/Client/Async.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.55
        ? ( BUILD_REQUIRES => {
                'RPC::ExtDirect::Server' => '3.0',
            },
            PREREQ_PM => {
                'AnyEvent::HTTP'         => 0,
                'RPC::ExtDirect::Client' => '3.0',
            },
        )
        : ( PREREQ_PM => {
                'AnyEvent::HTTP'         => 0,
                'RPC::ExtDirect::Server' => '3.0',
                'HTTP::Tiny'             => '0.014',
                'JSON'                   => '2.0',
            },
        )
    ),

    ABSTRACT => 'Asynchronous Ext.Direct client in Perl',
    AUTHOR   => 'Alex Tokarev <tokarev@cpan.org>',
    LICENSE  => 'perl',

    ($ExtUtils::MakeMaker::VERSION >= 6.46
        ? ( META_MERGE => {
                resources => {
                    bugtracker => 'http://github.com/nohuhu/RPC-ExtDirect-Client-Async/issues',
                    repository => 'http://github.com/nohuhu/RPC-ExtDirect-Client-Async',
                },
            },
        )
        : ()
    ),
);


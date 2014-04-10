# Test asynchronous Ext.Direct request handling

use strict;
use warnings;
no  warnings 'uninitialized';

use File::Temp 'tempfile';
use Test::More;

use RPC::ExtDirect::Test::Util;
use RPC::ExtDirect::Server::Util;

eval {
    require AnyEvent::HTTP;
};

if ( $@ ) {
    plan skip_all => "AnyEvent::HTTP not present";
}
else {
    require RPC::ExtDirect::Client::Async;

    plan tests => 15;
}

use lib 't/lib';
use test::class;

my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $cclass = 'RPC::ExtDirect::Client::Async';

my $cv = AnyEvent->condvar;

my %client_params = (
    host => $host,
    port => $port,
    cv   => $cv,
);

my $client = eval { $cclass->new( %client_params ) };

is     $@,      '',      "Didn't die";
ok     $client,          'Got client object';
isa_ok $client, $cclass, 'Right object, too,';

my $arg_ordered = [ qw(foo bar qux mumble splurge) ];
my $exp_ordered = [ qw(foo bar qux) ];
my $arg_named = {
    arg1 => 'foo', arg2 => 'bar', arg3 => 'qux', arg4 => 'mumble'
};
my $exp_named = { arg1 => 'foo', arg2 => 'bar', arg3 => 'qux' };

my $timeout = 1;

# Ordered method call

$cv->begin;

$client->call_async(
    action => 'test',
    method => 'ordered',
    arg    => $arg_ordered,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, 'Ordered not exception';
        is_deeply $data, $exp_ordered, 'Ordered return data matches';

        $cv->end;
    },
    timeout => $timeout,
);

# Named method call

$cv->begin;

$client->call_async(
    action => 'test',
    method => 'named',
    arg    => $arg_named,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, 'Named not exception';
        is_deeply $data, $exp_named, 'Named return data matches';

        $cv->end;
    },
    timeout => $timeout,
);

# Form submit

$cv->begin;

my $fields = { foo => 'qux', bar => 'baz' };

$client->submit_async(
    action => 'test',
    method => 'handle_form',
    arg    => $fields,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, "Form not exception";
        is_deeply $data, $fields, "Form data match";

        $cv->end;
    },
);

# Form submit with file upload

# Generate some files with some random data
my @files = map { gen_file() } 0 .. int rand 9;

my $exp_upload = [
    map {
        { name => (File::Spec->splitpath($_))[2], size => (stat $_)[7] }
    }
    @files
];

$cv->begin;

$client->submit_async(
    action => 'test',
    method => 'handle_upload',
    upload => \@files,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, "Upload not exception";
        is_deeply $data, $exp_upload, "Upload data match";

        $cv->end;
    },
);

# Asynchronous polling

my $events = $test::class::EVENTS;

my $i = 0;

for my $test ( @$events ) {
    my $exp = { name => 'foo', data => $test };

    my $cb = sub {
        my $data = shift;

        is_deeply $data, $exp, "Poll $i data matches";

        $cv->end;
    };

    $cv->begin;

    $client->poll_async( cb => $cb );

    $i++;
}

$cv->recv;

sub gen_file {
    my ($fh, $filename) = tempfile;

    print $fh int rand 1000 for 0 .. int rand 1000;

    return $filename;
}


# Test exceptions and server failure handling

use strict;
use warnings;

use Test::More tests => 104;

use AnyEvent;
use AnyEvent::HTTP;
use RPC::ExtDirect::Client::Async;

use RPC::ExtDirect::Test::Util;
use RPC::ExtDirect::Server::Util;

use lib 't/lib';
use test::class;
use RPC::ExtDirect::Client::Async::Test::Util;

# Clean up %ENV so that AnyEvent::HTTP does not accidentally connect to a proxy
clean_env;

my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $cv = AnyEvent->condvar;

my $client = RPC::ExtDirect::Client::Async->new(
    host   => $host,
    port   => $port,
    cv     => $cv,
);

# This should die despite API not being ready
eval {
    $client->call_async(
        action => 'test',
        method => 'ordered', #exists
        arg    => [],
    )
};

like $@, qr{^Callback subroutine is required},
         "Died at no callback provided before ready";

# These calls should NOT die but pass the error to callback instead
run_batch(\&test_call, 'before API is ready');

# Block until we got API
$cv->recv;

# Sanity checks
is $client->api_ready, 1,     "Got API ready";
is $client->exception, undef, "No exception set";

# This should also die the same way as before API is ready
eval {
    $client->call_async(
        action => 'test',
        method => 'ordered', #exists
        arg    => [],
    )
};

like $@, qr{^Callback subroutine is required},
         "Died at no callback provided after ready";

# This should treat the cv as callback and pass the error on to it
my $cv2 = AnyEvent->condvar;

eval {
    $client->call_async(
        action => 'test',
        method => 'nonexistent',
        arg    => [],
        cb     => $cv2,
    )
};

is $@, '', "CV as callback eval $@";

my $want = [
    undef, '', 'Method nonexistent is not found in Action test'
];

# Block, but briefly
my $have = $cv2->recv;
my @have = $cv2->recv;

is       $have, undef, "CV as callback result scalar context";
is_deep \@have, $want, "CV as callback result list context";

# These calls should behave the same way as before API is ready,
# i.e. not die but pass the error to the callback
run_batch(\&test_call, 'after API is ready');

sub test_call {
    my (%arg) = @_;
    
    my $client = delete $arg{client};
    my $err_re = delete $arg{err_re};
    my $msg    = delete $arg{msg};
    my $type   = delete $arg{type} || 'call';
    
    my $sub_name = "${type}_async";
    
    eval {
        $client->$sub_name(
            cb => sub {
                my ($result, $success, $error) = @_;
                
                is   $result,   undef,   "$msg result";
                ok   !$success,          "$msg success";
                like $error,    $err_re, "$msg error";
            },
            %arg,
        )
    };
    
    is $@, '', "$msg didn't die";
}

sub run_batch {
    my ($runner, $phase) = @_;

    # Call to a nonexistent Action
    $runner->(
        client => $client,
        msg    => "($phase) Nonexistent Action",
        err_re => qr{Action nonexistent is not found},
        action => 'nonexistent',
        method => 'nonexistent2',
        arg    => [],
    );

    # Call to a nonexistent Method
    $runner->(
        client => $client,
        msg    => "($phase) Nonexistent Method",
        err_re => qr{^Method nonexistent is not found},
        action => 'test',
        method => 'nonexistent',
        arg    => [],
    );

    # Ordered arguments are missing
    $runner->(
        client => $client,
        msg    => "($phase) Missing ordered arguments",
        err_re => qr{expects ordered arguments in arrayref},
        action => 'test',
        method => 'ordered',
    );

    # Wrong ordered arguments
    $runner->(
        client => $client,
        msg    => "($phase) Ordered arguments of wrong type",
        err_re => qr{expects ordered arguments in arrayref},
        action => 'test',
        method => 'ordered',
        arg    => {},
    );

    # Not enough ordered arguments
    $runner->(
        client => $client,
        msg    => "($phase) Not enough ordered arguments",
        err_re => qr{requires 3 argument\(s\) but only 1 are provided},
        action => 'test',
        method => 'ordered',
        arg    => [42],
    );

    # Missing named arguments
    $runner->(
        client => $client,
        msg    => "($phase) Missing named arguments",
        err_re => qr{expects named arguments in hashref},
        action => 'test',
        method => 'named',
    );

    # Wrong named arguments
    $runner->(
        client => $client,
        msg    => "($phase) Named arguments of wrong type",
        err_re => qr{expects named arguments in hashref},
        action => 'test',
        method => 'named',
        arg    => [],
    );

    # Not enough named arguments
    $runner->(
        client => $client,
        msg    => "($phase) Not enough named args strict",
        err_re => qr{parameters: 'arg1, arg2, arg3'; these are missing: 'arg3'},
        action => 'test',
        method => 'named',
        arg    => { arg1 => 'foo', arg2 => 'bar', },
    );

    # Not enough required parameters !strict
    $runner->(
        client => $client,
        msg    => "($phase) Not enough named args !strict",
        err_re => qr{parameters: 'arg1, arg2'; these are missing: 'arg2'},
        action => 'test',
        method => 'named_no_strict',
        arg    => { arg1 => 'foo', },
    );
    
    # Missing arguments for formHandler
    $runner->(
        client => $client,
        msg    => "($phase) Missing formHandler arguments",
        err_re => qr{expects named arguments in hashref},
        action => 'test',
        method => 'handle_form',
        type   => 'submit',
    );

    # Wrong argument type for formHandler
    $runner->(
        client => $client,
        msg    => "($phase) Wrong argument type for formHandler",
        err_re => qr{expects named arguments in hashref},
        action => 'test',
        method => 'handle_form',
        arg    => [],
        type   => 'submit',
    );

    # Nonexistent or unreadable upload
    $runner->(
        client => $client,
        msg    => "($phase) Unreadable upload",
        err_re => qr{Upload entry 'nonexistent_file' is not readable},
        action => 'test',
        method => 'handle_form',
        upload => ['nonexistent_file'],
        type   => 'upload',
    );
}

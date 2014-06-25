# Test asynchronous Ext.Direct Method calls via POST

use strict;
use warnings;

use Test::More tests => 8;

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

my $arg_ordered = [ qw(foo bar qux mumble splurge) ];
my $exp_ordered = [ qw(foo bar qux) ];
my $arg_named = {
    arg1 => 'foo', arg2 => 'bar', arg3 => 'qux', arg4 => 'mumble'
};
my $exp_named = { arg1 => 'foo', arg2 => 'bar', arg3 => 'qux' };

# Ordered method call
$client->call_async(
    action => 'test',
    method => 'ordered',
    arg    => $arg_ordered,
    cv     => $cv,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, 'Ordered not exception';
        is_deep $data, $exp_ordered, 'Ordered return data matches';
    },
);

# Named method call
$client->call_async(
    action => 'test',
    method => 'named',
    arg    => $arg_named,
    cv     => $cv,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, 'Named not exception';
        is_deep $data, $exp_named, 'Named return data matches';
    },
);

# Named method with no strict argument checking
$client->call_async(
    action => 'test',
    method => 'named_no_strict',
    arg    => $arg_named,
    cv     => $cv,
    cb     => sub {
        my $data = shift;
        
        unlike ref $data, qr/Exception/, 'Named !strict not exception';
        is_deep $data, $arg_named, 'Named no strict return data matches';
    },
);

# Block until all tests above finish
$cv->recv;

# Test cv as the callback
$cv = AnyEvent->condvar;

$client->call_async(
    action => 'test',
    method => 'ordered',
    arg    => [41, 42, 43],
    cb     => $cv,
);

# This should block
my $have = $cv->recv;

is_deep $have, [41, 42, 43], "cv as callback data matches";


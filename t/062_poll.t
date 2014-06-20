# Test asynchronous poll handling for individual events

use strict;
use warnings;

use Test::More tests => 5;

use AnyEvent;
use AnyEvent::HTTP;
use RPC::ExtDirect::Client::Async;

use RPC::ExtDirect::Test::Util;
use RPC::ExtDirect::Server::Util;

use lib 't/lib';
use test::class;

my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $cv = AnyEvent->condvar;

my $client = RPC::ExtDirect::Client::Async->new(
    host => $host,
    port => $port,
    cv   => $cv,
);

ok $client, 'Got client object';

my $events = $test::class::EVENTS;

my $i = 0;

for my $test ( @$events ) {
    my $want = [{ name => 'foo', data => $test }];
    my $desc = "Poll $i data matches";

    my $cb = sub {
        is_deep shift, $want, $desc;
    };

    $client->poll_async(
        cv => $cv,
        cb => $cb,
    );

    $i++;
}

# Block until all tests finish
$cv->recv;


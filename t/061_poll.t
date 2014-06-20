# Test event poll handling for empty responses

package test::class;

use strict;

use RPC::ExtDirect;
use RPC::ExtDirect::Event;

sub handle_poll : ExtDirect(pollHandler) { return; }

package main;

use strict;
use warnings;

use Test::More tests => 3;

use AnyEvent;
use AnyEvent::HTTP;
use RPC::ExtDirect::Client::Async;

use RPC::ExtDirect::Test::Util;
use RPC::ExtDirect::Server::Util;

my ($host, $port) = maybe_start_server(static_dir => 't/htdocs');
ok $port, "Got host: $host and port: $port";

my $cv = AnyEvent->condvar;

my $client = RPC::ExtDirect::Client::Async->new(
    host   => $host,
    port   => $port,
    cv     => $cv,
);

ok $client, 'Got client object';

$client->poll_async(
    cv => $cv,
    cb => sub {
        is_deep shift, [], "Empty poll response";
    },
);

# Block until all tests finish
$cv->recv;


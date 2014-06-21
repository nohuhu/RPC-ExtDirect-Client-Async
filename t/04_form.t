# Test asynchronous Ext.Direct form submits

use strict;
use warnings;

use Test::More tests => 3;

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

# Form submit
my $fields = { foo => 'qux', bar => 'baz' };

$client->submit_async(
    action => 'test',
    method => 'handle_form',
    arg    => $fields,
    cv     => $cv,
    cb     => sub {
        my $data = shift;

        unlike ref $data, qr/Exception/, "Form not exception";
        is_deep $data, $fields, "Form data match";
    },
);

# Block until all tests finish
$cv->recv;


package RPC::ExtDirect::Client::Async;

use strict;
use warnings;
no  warnings 'uninitialized';

use Carp;
use File::Spec;
use HTTP::Tiny;
use AnyEvent::HTTP;

use RPC::ExtDirect::Util::Accessor;
use RPC::ExtDirect::Config;
use RPC::ExtDirect::API;
use RPC::ExtDirect;
use RPC::ExtDirect::Client;

use base 'RPC::ExtDirect::Client';

#
# This module is not compatible with RPC::ExtDirect < 3.0
#

croak __PACKAGE__." requires RPC::ExtDirect 3.0+"
    if $RPC::ExtDirect::VERSION lt '3.0';

### PACKAGE GLOBAL VARIABLE ###
#
# Module version
#

our $VERSION = '3.00_01';

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new Async client, connect to the specified server
# and initialize the Ext.Direct API. Optionally fire a callback
# when that's done
#

sub new {
    my ($class, %params) = @_;
    
    my $api_cb = delete $params{api_cb};
    
    my $self = $class->SUPER::new(%params);
    
    $self->api_cb($api_cb);
    
    return $self;
}

### PUBLIC INSTANCE METHOD ###
#
# Call specified Action's Method asynchronously
#

sub call_async { shift->async_request('call', @_) }

### PUBLIC INSTANCE METHOD ###
#
# Submit a form to specified Action's Method asynchronously
#

sub submit_async { shift->async_request('form', @_) }

### PUBLIC INSTANCE METHOD ###
#
# Upload a file using POST form. Same as submit()
#

*upload_async = *submit_async;

### PUBLIC INSTANCE METHOD ###
#
# Poll server for events asynchronously
#

sub poll_async { shift->async_request('poll', @_) }

### PUBLIC INSTANCE METHOD ###
#
# Run a specified request type asynchronously
#

sub async_request {
    my $self = shift;
    my $type = shift;
    
    my $tr_class    = $self->transaction_class;
    my $transaction = $tr_class->new(@_);
    
    #
    # We try to avoid action-at-a-distance here, so we will
    # call all the stuff that could die() up front,
    # to pass on the exception to the caller immediately
    # rather than blowing up later on.
    #
    eval { $self->_async_request($type, $transaction) };
    
    if ($@) { croak 'ARRAY' eq ref($@) ? $@->[0] : $@ };
    
    # Stay positive
    return 1;
}

### PUBLIC INSTANCE METHOD ###
#
# Return the name of the Transaction class
#

sub transaction_class { 'RPC::ExtDirect::Client::Async::Transaction' }

### PUBLIC INSTANCE METHOD ###
#
# Read-write accessor
#

RPC::ExtDirect::Util::Accessor->mk_accessor(
    simple => [qw/ api_ready api_cb request_queue /],
);

############## PRIVATE METHODS BELOW ##############

### PRIVATE INSTANCE METHOD ###
#
# Throw an exception using the condvar passed to the constructor,
# or just set an error so the next async request would die() with it
#

sub _throw {
    my ($self, $ex) = @_;
    
    my $cv = $self->cv;
    
    if ($cv) {
        $cv->croak($ex);
    }
    else {
        push @{$self->{exceptions}}, $ex;
    }
}

### PRIVATE INSTANCE METHOD ###
#
# Initialize API declaration
#

sub _init_api {
    my ($self) = @_;
    
    # We want to be truly asynchronous, so instead of
    # blocking on API retrieval, we create a request queue
    # and return immediately. If any call/form/poll requests happen
    # before we've got the API result back, we push them in the queue
    # and wait for the API to arrive, then re-run the requests.
    # After the API declaration has been retrieved, all subsequent
    # requests run without queuing.
    $self->request_queue([]);

    $self->_get_api(sub {
        my ($success, $api_js, $error) = @_;
        
        if ( $success ) {
            $self->_import_api($api_js);
            $self->api_ready(1);
        
            my $queue = $self->request_queue;
            delete $self->{request_queue};  # A bit quirky
        
            $_->() for @$queue;
        }
        
        $self->api_cb->($self, $success, $error) if $self->api_cb;
    });
}

### PRIVATE INSTANCE METHOD ###
#
# Receive API declaration from specified server,
# parse it and return Client::API object
#

sub _get_api {
    my ($self, $cb) = @_;

    my $cv     = $self->cv;
    my $uri    = $self->_get_uri('api');
    my $params = $self->{http_params};
    
    # Run additional checks before firing curried callback
    my $api_cb = sub {
        my ($content, $headers) = @_;

        my $status         = $headers->{Status};
        my $content_length = do { use bytes; length $content; };
        my $success        = $status eq '200' && $content_length > 0;
        my $error;
        
        if ( !$success ) {
            if ( $status ne '200' ) {
                $error = "Can't download API declaration: $status";
            }
            elsif ( !$content_length ) {
                $error = "Empty API declaration received";
            }
            
            if ( $error ) {
                if ( $cv ) {
                    $cv->croak($error);
                }
                else {
                    $self->_throw($error);
                }
            }
        }

        $cv->end if $cv;
        
        $self->{api_guard} = undef;
        
        $cb->($success, $content, $error);
    };
    
    $cv->begin if $cv;

    # Store "cancellation guard" to prevent it being destroyed prematurely
    $self->{api_guard} = AnyEvent::HTTP::http_request(
        GET => $uri,
        %$params,
        $api_cb,
    );
}

### PRIVATE INSTANCE METHOD ###
#
# Run asynchronous request(s) if the API is already available;
# queue for later if not
#

sub _run_request {
    my $self = shift;
    
    if ( $self->api_ready ) {
        $_->() for @_;
    }
    else {
        $self->_queue_request(@_);
    }
}

### PRIVATE INSTANCE METHOD ###
#
# Queue asynchronous request(s)
#

sub _queue_request {
    my $self = shift;
    
    my $queue = $self->{request_queue};
    
    push @$queue, @_;
}

### PRIVATE INSTANCE METHOD ###
#
# Make an HTTP request in asynchronous fashion
#

sub _async_request {
    my ($self, $type, $transaction) = @_;
    
    $self->_run_request(sub {
        my $prepare = "_prepare_${type}_request";
        my $method  = $type eq 'poll' ? 'GET' : 'POST';
    
        $transaction->start;
        
        my ($uri, $request_content, $http_params, $request_options)
            = eval { $self->$prepare($transaction) };
        
        $transaction->finish('ARRAY' eq ref $@ ? $@->[0] : $@, !1)
            if $@;
    
        my $request_headers = $request_options->{headers};

        # TODO Handle errors
        my $guard = AnyEvent::HTTP::http_request(
            $method, $uri,
            headers    => $request_headers,
            body       => $request_content,
            persistent => !1,
            %$http_params,
            $self->_curry_response_cb($type, $transaction),
        );
        
        $transaction->guard($guard);
    });
}

### PRIVATE INSTANCE METHOD ###
#
# Parse cookies if provided, creating Cookie header
#

sub _parse_cookies {
    my ($self, $to, $from) = @_;
    
    $self->SUPER::_parse_cookies($to, $from);
    
    # This results in Cookie header being a hashref,
    # but we need a string for AnyEvent::HTTP
    if ( $to->{headers} && (my $cookies = $to->{headers}->{Cookie}) ) {
        $to->{headers}->{Cookie} = join '; ', @$cookies;
    }
}

### PRIVATE INSTANCE METHOD ###
#
# Generate result handling callback
#

sub _curry_response_cb {
    my ($self, $type, $transaction) = @_;
    
    return sub {
        my ($data, $headers) = @_;
        
        my $status  = $headers->{Status};
        my $success = $status eq '200';
        
        my $handler  = "_handle_${type}_response";
        my $response = eval {
            $self->$handler({
                status  => $status,
                success => $success,
                content => $data,
            })
        } if $success;
        
        # We're only interested in the data, but anything goes
        my $result = 'ARRAY' eq ref($@)       ? $@->[0]
                   : $@                       ? $@
                   : !$success                ? $headers->{Reason}
                   : 'poll' eq $type          ? $response
                   : 'HASH' eq ref($response) ? $response->{result}
                   :                            $response
                   ;
        
        $transaction->finish($result, !$@ && $success);
    };
}

package
    RPC::ExtDirect::Client::Async::Transaction;

use Carp;

use base 'RPC::ExtDirect::Client::Transaction';

my @fields = qw/ cb cv actual_arg fields /;

sub new {
    my ($class, %params) = @_;
    
    croak "Callback subroutine is required"
        unless 'CODE' eq ref $params{cb};
    
    my %self_params = map { $_ => delete $params{$_} } @fields;
    
    my $self = $class->SUPER::new(%params);
    
    @$self{ keys %self_params } = values %self_params;
    
    return $self;
}

sub start {
    my ($self) = @_;
    
    my $cv = $self->cv;
    
    $cv->begin if $cv;
}

sub finish {
    my ($self, $result, $success) = @_;
    
    my $cb = $self->cb;
    my $cv = $self->cv;
    
    $cb->($result, $success) if $cb;
    $cv->end                 if $cv;
}

RPC::ExtDirect::Util::Accessor->mk_accessors(
    simple => [qw/ cb cv guard /],
);

1;

#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use open qw/ :encoding(UTF-8) :std /;
use Test::More;
use Test::Fatal;
use JSON::XS;
use Monitoring::Icinga2::Client::Simple;

my @start_end = (
    start_time => 1_234_567_890,
    end_time   => 1_234_567_890 + 60,
);

my $uri_base     = 'https://localhost:5665/v1';
my $uri_scheddt  = "$uri_base/actions/schedule-downtime";
my $uri_removedt = "$uri_base/actions/remove-downtime";
my $uri_custnot  = "$uri_base/actions/send-custom-notification";
my $uri_hosts    = "$uri_base/objects/hosts/";
my $uri_services = "$uri_base/objects/services/";
my $uri_app      = "$uri_base/objects/icingaapplications/app";
my $uri_status   = "$uri_base/status/IcingaApplication";

my $fil_host     = '"filter":"host.name==\"localhost\""';
my $fil_hostsrv  = '"filter":"host.name==\"localhost\" && service.name==\"myservice\""';

my $req_frag1 = '{"author":"admin","comment":"no comment","duration":null,"end_time":1234567950,"filter":"host.name==\"localhost\"';
my $req_frag2 = $req_frag1 . '","fixed":null,"joins":["host.name"],"start_time":1234567890,"type":';

my $req_dthost   = $req_frag2 . '"Host"}';
my $req_dtservs  = $req_frag2 . '"Service"}';
my $req_dtserv   = $req_frag1 . ' && service.name==\"myservice\"","fixed":null,"joins":["host.name"],"start_time":1234567890,"type":"Service"}';
(my $req_dthostu = $req_dthost) =~ s/admin/POSIX::cuserid()/e;

like(
    exception { Monitoring::Icinga2::Client::Simple->new(1) },
    qr/^only hash-style args are supported/,
    'constructor catches wrong calling style'
);

like(
    exception { Monitoring::Icinga2::Client::Simple->new( foo => 1 ) },
    qr/^`hostname' arg is required/,
    'constructor catches missing hostname arg'
);

is(
    exception { Monitoring::Icinga2::Client::Simple->new( hostname => 'foo' ) },
    undef,
    'hostname is the only mandatory argument'
);

req_fail(
    'schedule_downtime',
    [ host => 'localhost' ],
    qr/^Missing or undefined argument `start_time'/,
    "detects missing args"
);

req_ok(
    'schedule_downtime',
    [ host => 'localhost', @start_end, comment => 'no comment', author => 'admin', ], 
    [ $uri_scheddt => $req_dthost ],
    "schedule_downtime"
);

req_ok(
    'schedule_downtime',
    [ host => 'localhost', @start_end, comment => 'no comment', author => 'admin', services => 1 ], 
    [
        $uri_scheddt => $req_dthost,
        $uri_scheddt => $req_dtservs,
    ],
    "schedule_downtime w/services"
);

req_ok(
    'schedule_downtime',
    [ host => 'localhost', @start_end, comment => 'no comment', author => 'admin', service => 'myservice' ], 
    [ $uri_scheddt => $req_dtserv ],
    "schedule_downtime w/single service"
);

req_ok(
    'schedule_downtime',
    [ host => 'localhost', @start_end, comment => 'no comment', author => 'admin', service => 'myservice', services => 1 ], 
    [
        $uri_scheddt => $req_dthost,
        $uri_scheddt => $req_dtservs,
    ],
    "schedule_downtime w/both service and services specified "
);

req_ok(
    'schedule_downtime',
    [ host => 'localhost', @start_end, comment => 'no comment' ], 
    [ $uri_scheddt => $req_dthostu ],
    "schedule_downtime w/o explicit author"
);

req_ok(
    'remove_downtime',
    [ host => 'localhost', service => 'myservice' ], 
    [
        $uri_removedt => '{' . $fil_hostsrv . ',"joins":["host.name"],"type":"Service"}'
    ],
    "remove_downtime w/single service"
);

req_ok(
    'remove_downtime',
    [ host => 'localhost' ], 
    [
        $uri_removedt => '{' . $fil_host . ',"joins":["host.name"],"type":"Host"}'
    ],
    "remove_downtime w/host only"
);

req_ok(
    'remove_downtime',
    [ name => 'foobar' ], 
    [
        "$uri_removedt\\?downtime=foobar" => '{"type":"Downtime"}'
    ],
    "remove_downtime by name"
);

req_ok(
    'send_custom_notification',
    [ comment => 'mycomment', author => 'admin', host => 'localhost' ], 
    [
        $uri_custnot => '{"author":"admin","comment":"mycomment","filter":"host.name==\"localhost\"","type":"Host"}'
    ],
    "send custom notification for host"
);

req_ok(
    'send_custom_notification',
    [ comment => 'mycomment', author => 'admin', service => 'myservice' ], 
    [
        $uri_custnot => '{"author":"admin","comment":"mycomment","filter":"service.name==\"myservice\"","type":"Service"}'
    ],
    "send custom notification for service"
);

req_ok(
    'send_custom_notification',
    [ comment => 'mycomment', service => 'myservice' ], 
    [
        $uri_custnot => sprintf(
            '{"author":"%s","comment":"mycomment","filter":"service.name==\"myservice\"","type":"Service"}',
            POSIX::cuserid()
        )
    ],
    "send custom notification w/o explicit author"
);

req_ok(
    'notifications',
    [ 1, host => 'localhost' ], 
    [
        $uri_hosts => '{"attrs":{"enable_notifications":"1"},"filter":"host.name==\"localhost\""}'
    ],
    "enable notifications for host"
);

req_ok(
    'notifications',
    [ 1, host => 'localhost', service => 'myservice' ], 
    [
        $uri_services => '{"attrs":{"enable_notifications":"1"},'. $fil_hostsrv .'}'
    ],
    "enable notifications for service"
);

req_fail(
    'notifications',
    [ 1, service => 'myservice' ], 
    qr/`host' argument missing/,
    "catches missing host argument"
);

req_fail(
    'notifications',
    [ ], 
    qr'\$state is required to be a boolean value',
    "catches missing state"
);

req_ok(
    'query_app_attrs',
    [ ], 
    [
        $uri_status => ''
    ],
    "query application attributes"
);

req_ok(
    'set_app_attrs',
    [ flapping => 1, notifications => 0, perfdata => 1 ], 
    [
        $uri_app => '{"attrs":{"enable_flapping":"1","enable_notifications":"","enable_perfdata":"1"}}'
    ],
    "set application attributes"
);

req_fail(
    'set_app_attrs',
    [ foo => 1 ],
    qr/^Need at least one argument of/,
    "detects missing valid args"
);

req_fail(
    'set_app_attrs',
    [ foo => 1, notifications => 0, bar => 'qux' ],
    qr/^Unknown attributes: bar,foo; legal attributes are: event_handlers,/,
    "detects invalid arg"
);

req_ok(
    'global_notifications',
    [ 1 ], 
    [
        $uri_app => '{"attrs":{"enable_notifications":"1"}}'
    ],
    "enable global notifications"
);

done_testing;

sub req_ok {
    my ($method, $margs, $req_cont, $desc) = @_;
    my $c = newob();
    is(
        exception { $c->$method( @$margs ) },
        undef,
        "$desc: arg check passes for $method",
    ) and checkreq( $c, $req_cont, $desc );
}

sub req_fail {
    my ($method, $margs, $except_re, $desc) = @_;
    my $c = newob();
    like(
        exception { $c->$method( @$margs ) },
        $except_re,
        "$method fails: $desc",
    );
}

sub checkreq {
    my ($c, $req_contents, $desc) = @_;

    my $calls = $c->{ua}->calls;
    
    my $i = 1;
    for my $req ( grep { $_->{method} eq 'FakeUA::request' } @$calls ) {
        my ($uri, $content) = splice @$req_contents, 0, 2;
        # fix up uri to account for a concatenation bug that might be fixed
        $uri =~ s!/v1/!/v1//?!;
        like( $req->{args}[0]->uri, qr/^$uri$/, "$desc (uri $i)" );
        is( _decenc( $req->{args}[0]->content ), $content, "$desc (req $i)" );
        $i++;
    }
}


sub newob {
    return Monitoring::Icinga2::Client::Simple->new(
        hostname => 'localhost',
        useragent => FakeUA->new,
    );
}

sub _decenc {
    my $s = shift;
    return $s unless defined $s and length $s;
    my $codec = JSON::XS->new->canonical;
    return $codec->encode(
        $codec->decode( $s )
    );
}

package FakeUA;
use Clone 'clone';
use strict;
use warnings;

sub new {
    return bless {
        calls => [],
    }, shift;
}

sub credentials { _logcall(@_); }
sub default_header { _logcall(@_) }

sub request {
    my $self = shift;
    my $req = $_[0];
    $self->_logcall( @_ );

    my $content = '{"results":[]}';
    if( $req->uri =~ m!/status/IcingaApplication$! ) {
        $content = '{"results":[{"status":{"icingaapplication":{"app":[]}}}]}'
    }
    
    return HTTP::Response->new( 200, 'OK', undef, $content );
}

sub calls {
    return shift->{calls};
}

sub _logcall {
    my $self = shift;
    my $sub = ( caller(1) )[3];
    push @{ $self->{calls} }, {
        method => $sub,
        args => clone(\@_),
    };
}

# ABSTRACT: Simpler REST client for Icinga2

package Monitoring::Icinga2::Client::Simple;

use strict;
use warnings;
use 5.010_001;
use Monitoring::Icinga2::Client::REST 2;
use parent -norequire, 'Monitoring::Icinga2::Client::REST';
use Carp;
use List::Util qw/ all any first /;
use constant DEBUG => $ENV{DEBUG};

sub new {
    my $class = shift;
    croak( "only hash-style args are supported" ) if @_ % 2;
    my %args = @_;
    # uncoverable condition false
    my $server = delete $args{server} // croak( "`server' arg is required" );
    my $ua = delete $args{useragent};
    my $self = $class->SUPER::new( $server, %args );
    if( defined $ua ) {
        # This is a hack as I don't maintain the superclass. However, I wrote its
        # constructor and we'll check whether it has changed so it should be fine.
        # uncoverable branch true
        defined $self->{ua} or croak( 'Monitoring::Icinga2::Client::REST seems to have changed internals; '. 'passing `useragent\' does not work. Please notify mbethke@cpan.org');
        $ua->default_header( 'Accept' => 'application/json' );
        $self->{ua} = $ua;
        # uncoverable condition false
        # uncoverable branch right
        $self->{_mics_author} = getlogin || getpwuid($<);
    }
    return $self;
}

sub schedule_downtime {
    my ($self, %args) = @_;
    _checkargs(\%args, qw/ start_time end_time comment host /);
    # uncoverable condition true
    $args{author} //= $self->{_mics_author};

    if( $args{service} and not $args{services} ) {
        return [ $self->_schedule_downtime_type( 'Service', \%args) ];
    }

    delete $args{service};  # make sure _schedule_downtime_type doesn't set a wrong filter
    my @results = $self->_schedule_downtime_type( 'Host', \%args );
    push @results, $self->_schedule_downtime_type( 'Service', \%args ) if $args{services};
    return \@results;
}

sub _schedule_downtime_type {
    my ($self, $type, $args) = @_;
    my $req_results = $self->_request('POST',
        '/actions/schedule-downtime',
        {
            type => $type,
            joins => [ "host.name" ],
            filter => _create_filter( $args ),
            map { $_ => $args->{$_} } qw/ author start_time end_time comment duration fixed /
        }
    );
    return @$req_results;
}

sub remove_downtime {
    my ($self, %args) = @_;

    defined $args{name}
        and return $self->_remove_downtime_type( 'Downtime', "downtime=$args{name}" );

    _checkargs(\%args, 'host');

    defined $args{service}
        and return $self->_remove_downtime_type( 'Service', \%args );

    return $self->_remove_downtime_type( 'Host', \%args );
}

sub _remove_downtime_type {
    my ($self, $type, $args) = @_;
    my @post_args;

    if(ref $args) {
        @post_args = (
            undef,
            {
                type => $type,
                joins => [ "host.name" ],
                filter => _create_filter( $args ),
            }
        );
    } else {
        @post_args = ( $args, { type => $type } );
    }
    my $req_results = $self->_request('POST',
        "/actions/remove-downtime",
        @post_args,
    );
    return $req_results;
}

sub send_custom_notification {
    my ($self, %args) = @_;
    _checkargs(\%args, qw/ comment /);
    _checkargs_any(\%args, qw/ host service /);

    my $obj_type = defined $args{host} ? 'host' : 'service';

    return $self->_request('POST',
        '/actions/send-custom-notification',
        {
            type => ucfirst $obj_type,
            filter => "$obj_type.name==\"$args{$obj_type}\"",
            comment => $args{comment},
            # uncoverable condition false
            # uncoverable branch right
            author => $args{author} // $self->{_mics_author},
        }
    );
}

sub set_notifications {
    my ($self, %args) = @_;
    _checkargs(\%args, qw/ state /);
    _checkargs_any(\%args, qw/ host service /);
    my $uri_object = $args{service} ? 'services' : 'hosts';

    return $self->_request('POST',
        "/objects/$uri_object",
        {
            attrs => { enable_notifications => !!$args{state} },
            filter => _create_filter( \%args ),
        }
    );
}

sub query_app_attrs {
    my ($self) = @_;

    my $r = $self->_request('GET',
        "/status/IcingaApplication",
    );
    # uncoverable branch true
    # uncoverable condition left
    # uncoverable condition right
    ref $r eq 'ARRAY' and defined $r->[0] and defined $r->[0]{status}{icingaapplication}{app} or die "Invalid result from Icinga";

    return $r->[0]{status}{icingaapplication}{app};
}

{
    my %legal_attrs = map { $_ => 1 } qw/
    event_handlers
    flapping
    host_checks
    notifications
    perfdata
    service_checks
    /;

    sub set_app_attrs {
        my ($self, %args) = @_;
        _checkargs_any(\%args, keys %legal_attrs);
        my @unknown_attrs = grep { not exists $legal_attrs{$_} } keys %args;
        @unknown_attrs and croak(
            sprintf "Unknown attributes: %s; legal attributes are: %s",
            join(",", sort @unknown_attrs),
            join(",", sort keys %legal_attrs),
        );

        return $self->_request('POST',
            '/objects/icingaapplications/app',
            {
                attrs => {
                    map { 'enable_' . $_ => !!$args{$_} } keys %args
                },
            }
        );
    }
}

sub set_global_notifications {
    my ($self, $state) = @_;
    $self->set_app_attrs( notifications => $state );
}

sub query_host {
    my ($self, %args) = @_;
    _checkargs(\%args, qw/ host /);
    return $self->_request('GET',
        '/objects/hosts',
        { filter => "host.name==\"$args{host}\"" }
    )->[0];
}

sub query_child_hosts {
    my ($self, %args) = @_;
    _checkargs(\%args, qw/ host /);
    return $self->_request('GET',
        '/objects/hosts',
        { filter => "\"$args{host}\" in host.vars.parents" }
    );
}

sub query_services {
    my ($self, %args) = @_;
    _checkargs(\%args, qw/ service /);
    return $self->_request('GET',
        '/objects/services',
        { filter => "service.name==\"$args{service}\"" }
    );
}

sub _request {
    my ($self, $method, $url, $getargs, $postdata) = @_;

    if(defined $getargs and ref $getargs) {
        # getargs must be a string. if it ain't, it's actually postdata
        $postdata = $getargs;
        undef $getargs;
    }
    # uncoverable branch true
    my $r = $self->do_request($method, $url, $getargs, $postdata)
        or die $self->request_status_line . "\n";
    return $r->{results};
}

# Make sure at all keys are defined in the hash referenced by the first arg
# Not a method!
sub _checkargs {
    my $args = shift;

    all { defined $args->{$_} } @_ or croak(
        sprintf "missing or undefined argument `%s' to %s()",
        ( first { not defined $args->{$_} } @_ ),
        (caller(1))[3]
    );
}

# Make sure at least one key is defined in the hash referenced by the first arg
# Not a method!
sub _checkargs_any {
   my $args = shift;

   any { defined $args->{$_} } grep { exists $args->{$_} } @_ or croak(
       sprintf "need at least one argument of: %s to %s()",
       join(',', @_), (caller(1))[3]
   );
}

# Create a filter for a hostname in $args->{host} and optionally a service name in $args->{service}
# Not a method!
sub _create_filter {
    my $args = shift;
    croak( "`host' argument missing" ) unless defined $args->{host};
    my $filter = "host.name==\"$args->{host}\"";
    $filter .= " && service.name==\"$args->{service}\"" if $args->{service};
    return $filter;
}

1;
__END__

=head1 SYNOPSIS

    use Monitoring::Icinga2::Client::Simple;
    use Data::Dumper;

    # Instantiate an Icinga2 API client
    my $ia = Monitoring::Icinga2::Client::Simple->new( server => 'monitoring.mycompany.org' );

    # Disable notifications application-wide
    $ia->set_global_notifications( 0 );

    # Schedule an hour of downtime for web-1 and all of its services
    $ia->schedule_downtime(
        host => 'web-1',
        services => 1;
        start_time => scalar(time),
        end_time => time + 3600,
        fixed => 1,
        comment => 'System maintenance',
    );

    # Print a summary of everything Icinga knows about web-1
    print Dumper( $ia->query_host( host => 'web-1' ) );


=head1 DESCRIPTION

This module subclasses L<Monitoring::Icinga2::Client::REST> to present a
higher-level interface for commonly used operations such as:

=for :list
* Scheduling and removing downtimes on hosts and services
* Enabling and disabling notifications for individual objects
* Setting and getting global flags like those found under "Monitoring Health" -- notifications, active checks etc.
* Finding child objects

L<Monitoring::Icinga2::Client::REST> can do all of this and more, but it
requires you to deal with Icinga's query language that's as complicated as it
is powerful. This module saves you the hassle for the most common jobs while
still allowing to make more specialized API calls yourself.

=method new

    $ia = Monitoring::Icinga2::Client::Simple->new( agent => $ua );
    $ia = Monitoring::Icinga2::Client::Simple->new( hostname => 'monitoring.mycompany.org' );

The constructor supports almost the same arguments as the one in
L<Monitoring::Icinga2::Client::REST>. The differences are:

=for :list
* Only the extensible hash style arguments are supported
* The C<$hostname> parameter is not a positional one but passed hash-style, too, under the key C<server>.
* An additional key C<useragent> allows to pass in your own L<LWP::UserAgent> object; this enables more complicated configurations like using TLS client certificates that would otherwise make the number of arguments explode.

Note that the C<useragent> injection is a bit of a hack as it meddles with the
superclass' internals. I originally wrote quite some code (including the
constructor) in L<Monitoring::Icinga2::Client::REST> but I dont maintain it;
nevertheless I don't see any reason why it should change.

=method schedule_downtime

    $ia->schedule_downtime(
        host => 'web-1',
        start_time => scalar(time),
        end_time => time + 3600,
        comment => 'System maintenance',
    );

Set a downtime on a host, a host and all services, or a single service

Mandatory arguments:

=for :list
* C<host>: the host name as it it known to Icinga
* C<start_time>: start time as a Unix timestamp
* C<end_time>: also a Unix timestamp
* C<comment>: any string describing the reason for this downtime

Optional arguments:

=for :list
* C<service>: set a downtime for only this service on C<host>. Ignored when combined with C<services>.
* C<services>: set to a true value to set downtimes on all of a host's services. Default is to set the downime on the host only.
* C<author>: will use L<getlogin()|perlfunc/getlogin> (or L<getpwuid|perlfunc/getpwuid> where that's unavailable) if unset
* C<fixed>: set to true for a fixed downtime, default is flexible

The method returns a list of hashes with one element for each downtime
successfully set. The following keys are available:

=for :list
* C<code>: HTTP result code. Should always be 200.
* C<legacy_id>: Icinga2 internal ID to refer to this downtime
* C<name>: a symbolic name to refer to this downtime in the API, e.g. to remove it later
* C<status>: human-readable status message

=method remove_downtime

    $ia->remove_downtime( name => "web-1!NTP!49747048-f8d9-4ecc-95a4-86aa4c1011a9" );
    $ia->remove_downtime( host => "web-1", service => 'NTP' );
    $ia->remove_downtime( host => "web-1", services => 1 );

Remove a downtime by name or host/service name

Arguments:

=for :list
* host
* service
* name
* services

Setting C<name> allows a single downtime to be removed by its name as returned
when scheduling it; other arguments are ignored in this case. Removing a
downtime by name does not affect other downtimes on the same object.

If C<host> or both C<host> and C<service> are used, I<all> downtimes on these
objects are deleted. Set C<services> to a true value and pass a C<host>
argument to also delete all of this host's service downtimes.


=method query_host

    $result = $ia->query_host( host => 'web-1' );
    say "$result->{attrs}{name}: $result->{attrs}{type}";

Query all information Icinga2 has on a certain host. The result is a hashref,
currently containing a single key C<attrs>. If the host is not found, C<undef>
is returned.

The only mandatory argument is C<host>.

=method query_child_hosts

    $results = $ia->query_child_hosts( host => 'hypervisor-1' );
    say "$_->{attrs}{name}: $_->{attrs}{type}" for @$results;

Query all host objects that have a certain host listed as a parent. The result
is a reference to a list of hashes like those returned by L</query_host>.

The only mandatory argument is C<host>.

=method query_services

    $result = $ia->query_services( service => 'HTTP' );
    say "$_->{attrs}{name}: $_->{attrs}{type}" for @$results;

Query all information Icinga2 has on a certain service. As services usually
have more than one instance, the result is a reference to a list of hashes,
each describing one instance.

The only mandatory argument is C<service>. Note that this is a singular as it
specifies a single service name while the method name is plural due to the
plurality of returned results.

=method send_custom_notification

    $ia->send_custom_notification( comment => 'Just kidding :)', service => 'HTTP' );

Send a user-defined notification text for a host or service to all notification
recipients for this object. The only mandatory argument is C<comment>, and
additionally one of C<host> and C<service> must be set.

Note that for this call C<host> and C<service> are mutually exclusive. If both
are present, C<host> wins.

=method set_notifications

    $ia->set_notifications( state => 0, host => 'web-1' );

Enable or disable notifications for a host or service. C<state> is a boolean
specifying whether to switch notifications on or off; C<host> or C<service>
specifiy the object.

Use L</set_global_notifications> to toggle notifications application-wide!


=method query_app_attrs

    $attrs = $ia->query_app_attrs;
    say $attrs->{node_name};

Returns a reference to a hash of values representing a bunch of Icinga
application attributes. The following are currently defined, although future
Icinga versions may return others:

=for :list
* C<enable_event_handlers>: boolean
* C<enable_flapping>: boolean
* C<enable_host_checks>: boolean
* C<enable_notifications>: boolean
* C<enable_perfdata>: boolean
* C<enable_service_checks>: boolean
* C<node_name>: string
* C<pid>: integer
* C<program_start>: floatingpoint timestamp
* C<version>: string


=method set_app_attrs

    $ia->set_app_attrs( host_checks => 0, flapping => 1 );

Set application attributes passed as hash-style arguments. Of the ones returned
by L</query_app_attrs>, only the booleans are settable; their names don't
include the `C<enable_>' prefix.

=method set_global_notifications

    $ia->set_global_notifications( 0 );

Convenience method to enable/disable global notifications, equivalent to
C<set_app_attrs( notifications =E<gt> $state)>. The only mandatory argument is
a boolean indicating whether to switch notifications on or off.

=cut


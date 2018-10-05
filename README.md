# NAME

Monitoring::Icinga2::Client::Simple

[![Build Status](https://travis-ci.org/mbethke/Monitoring-Icinga2-Client-Simple.png?branch=master)](https://travis-ci.org/mbethke/Monitoring-Icinga2-Client-Simple)

# VERSION

version 0.001000\_07

# SYNOPSIS

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

# DESCRIPTION

This module subclasses [Monitoring::Icinga2::Client::REST](https://metacpan.org/pod/Monitoring::Icinga2::Client::REST) to present a
higher-level interface for commonly used operations such as:

- Scheduling and removing downtimes on hosts and services
- Enabling and disabling notifications for individual objects
- Setting and getting global flags like those found under "Monitoring Health" -- notifications, active checks etc.
- Finding child objects

[Monitoring::Icinga2::Client::REST](https://metacpan.org/pod/Monitoring::Icinga2::Client::REST) can do all of this and more, but it
requires you to deal with Icinga's query language that's as complicated as it
is powerful. This module saves you the hassle for the most common jobs while
still allowing to make more specialized API calls yourself.

# METHODS

## new

    $ia = Monitoring::Icinga2::Client::Simple->new( agent => $ua );
    $ia = Monitoring::Icinga2::Client::Simple->new( hostname => 'monitoring.mycompany.org' );

The constructor supports almost the same arguments as the one in
[Monitoring::Icinga2::Client::REST](https://metacpan.org/pod/Monitoring::Icinga2::Client::REST). The differences are:

- Only the extensible hash style arguments are supported
- The `$hostname` parameter is not a positional one but passed hash-style, too, under the key `server`.
- An additional key `useragent` allows to pass in your own [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) object; this enables more complicated configurations like using TLS client certificates that would otherwise make the number of arguments explode.

Note that the `useragent` injection is a bit of a hack as it meddles with the
superclass' internals. I originally wrote quite some code (including the
constructor) in [Monitoring::Icinga2::Client::REST](https://metacpan.org/pod/Monitoring::Icinga2::Client::REST) but I dont maintain it;
nevertheless I don't see any reason why it should change.

## schedule\_downtime

    $ia->schedule_downtime(
        host => 'web-1',
        start_time => scalar(time),
        end_time => time + 3600,
        comment => 'System maintenance',
    );

Set a downtime on a host, a host and all services, or a single service

Mandatory arguments:

- `host`: the host name as it it known to Icinga
- `start_time`: start time as a Unix timestamp
- `end_time`: also a Unix timestamp
- `comment`: any string describing the reason for this downtime

Optional arguments:

- `service`: set a downtime for only this service on `host`. Ignored when combined with `services`.
- `services`: set to a true value to set downtimes on all of a host's services. Default is to set the downime on the host only.
- `author`: will use [getlogin()](https://metacpan.org/pod/perlfunc#getlogin) (or [getpwuid](https://metacpan.org/pod/perlfunc#getpwuid) where that's unavailable) if unset
- `fixed`: set to true for a fixed downtime, default is flexible

The method returns a list of hashes with one element for each downtime
successfully set. The following keys are available:

- `code`: HTTP result code. Should always be 200.
- `legacy_id`: Icinga2 internal ID to refer to this downtime
- `name`: a symbolic name to refer to this downtime in the API, e.g. to remove it later
- `status`: human-readable status message

## remove\_downtime

    $ia->remove_downtime( name => "web-1!NTP!49747048-f8d9-4ecc-95a4-86aa4c1011a9" );
    $ia->remove_downtime( host => "web-1", service => 'NTP' );
    $ia->remove_downtime( host => "web-1", services => 1 );

Remove a downtime by name or host/service name

Arguments:

- host
- service
- name
- services

Setting `name` allows a single downtime to be removed by its name as returned
when scheduling it; other arguments are ignored in this case. Removing a
downtime by name does not affect other downtimes on the same object.

If `host` or both `host` and `service` are used, _all_ downtimes on these
objects are deleted. Set `services` to a true value and pass a `host`
argument to also delete all of this host's service downtimes.

## query\_host

    $result = $ia->query_host( host => 'web-1' );
    say "$result->{attrs}{name}: $result->{attrs}{type}";

Query all information Icinga2 has on a certain host. The result is a hashref,
currently containing a single key `attrs`. If the host is not found, `undef`
is returned.

The only mandatory argument is `host`.

## query\_child\_hosts

    $results = $ia->query_child_hosts( host => 'hypervisor-1' );
    say "$_->{attrs}{name}: $_->{attrs}{type}" for @$results;

Query all host objects that have a certain host listed as a parent. The result
is a reference to a list of hashes like those returned by ["query\_host"](#query_host).

The only mandatory argument is `host`.

## query\_services

    $result = $ia->query_services( service => 'HTTP' );
    say "$_->{attrs}{name}: $_->{attrs}{type}" for @$results;

Query all information Icinga2 has on a certain service. As services usually
have more than one instance, the result is a reference to a list of hashes,
each describing one instance.

The only mandatory argument is `service`. Note that this is a singular as it
specifies a single service name while the method name is plural due to the
plurality of returned results.

## send\_custom\_notification

    $ia->send_custom_notification( comment => 'Just kidding :)', service => 'HTTP' );

Send a user-defined notification text for a host or service to all notification
recipients for this object. The only mandatory argument is `comment`, and
additionally one of `host` and `service` must be set.

Note that for this call `host` and `service` are mutually exclusive. If both
are present, `host` wins.

## set\_notifications

    $ia->set_notifications( state => 0, host => 'web-1' );

Enable or disable notifications for a host or service. `state` is a boolean
specifying whether to switch notifications on or off; `host` or `service`
specifiy the object.

Use ["set\_global\_notifications"](#set_global_notifications) to toggle notifications application-wide!

## query\_app\_attrs

    $attrs = $ia->query_app_attrs;
    say $attrs->{node_name};

Returns a reference to a hash of values representing a bunch of Icinga
application attributes. The following are currently defined, although future
Icinga versions may return others:

- `enable_event_handlers`: boolean
- `enable_flapping`: boolean
- `enable_host_checks`: boolean
- `enable_notifications`: boolean
- `enable_perfdata`: boolean
- `enable_service_checks`: boolean
- `node_name`: string
- `pid`: integer
- `program_start`: floatingpoint timestamp
- `version`: string

## set\_app\_attrs

    $ia->set_app_attrs( host_checks => 0, flapping => 1 );

Set application attributes passed as hash-style arguments. Of the ones returned
by ["query\_app\_attrs"](#query_app_attrs), only the booleans are settable; their names don't
include the \``enable_`' prefix.

## set\_global\_notifications

    $ia->set_global_notifications( 0 );

Convenience method to enable/disable global notifications, equivalent to
`set_app_attrs( notifications => $state)`. The only mandatory argument is
a boolean indicating whether to switch notifications on or off.

# AUTHOR

Matthias Bethke <matthias@towiski.de>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Matthias Bethke.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

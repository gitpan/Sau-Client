package Sau::Client;
use strict;
use Cache::FileCache;
use Carp qw(carp confess);
use LWP::UserAgent;
use Digest::SHA1 qw(sha1_hex);
use XML::Simple qw(XMLin);
use URI::Escape qw(uri_escape);
use vars qw($VERSION);

$VERSION = '0.51';

my $AUTH_VERSION = 1;

my $cache = Cache::FileCache->new({'namespace'          => __PACKAGE__,
				   'default_expires_in' => 86400, 
				  });

my $config;
my $config_base;
my $config_cache_key = "config:$VERSION:$AUTH_VERSION";

my $ua = LWP::UserAgent->new;
$ua->timeout(8);
$ua->agent("Sau::Client/$VERSION " . $ua->_agent);

sub new { 
  my $class = shift;
  my %args  = @_;
  my $self = bless {}, $class;
  if ($args{t} || $args{ticket}) {
    $self->_fetch_info(ticket => ($args{t} || $args{ticket}));
  }
  elsif ($args{session_id}) {
    $self->_get_info(session_id => $args{session_id});
  }
  return $self;
}

sub delete_session {
  my ($self, %args) = @_;
  my $session_id = $self->session_id;
  delete $self->{_session};
  delete $self->{_session_id};
  $self->_cache->remove("session_" . $session_id);
}

sub force_refresh {
  my ($self, $seconds) = @_;
  $seconds ||= 2;
  return 0 unless $self->data_age and $self->data_age >= $seconds;
  $self->_get_info(session_id => $self->session_id, force_refresh => 1);
  1;  # Hmn, should maybe return whatever _fetch_info gave us?
}

sub _get_info {
  my ($self, %args) = @_;
  return unless $args{session_id};

  $args{session_id} =~ s/[^a-f0-9]//gi;

  # Should we load from the cache even if we already have the session loaded in {_session} ?
  my $session = $self->_cache->get("session_" . $args{session_id});
  return unless $session and $session->{site_session};

  $self->{_session_id} = $args{session_id};

  $session->{last_refresh} = 0 if $args{force_refresh};

  if (($session->{last_refresh} + $self->config->{session_cache_time}) < time) {
    $self->_fetch_info(site_session => $session->{site_session});
  }
  else {
    $self->{_session} = $session;
  }
}

sub _fetch_info {
  my ($self, %args) = @_;
  my %parms;
  $parms{s} = $self->config->{site_id};
  if ($args{site_session}) {
    $parms{site_session} = $args{site_session};
  }
  elsif ($args{ticket}) {
    $parms{t} = $args{ticket}; 
  } 
  else {
    confess "no ticket or site_session passed to _fetch_info";
    return; 
  }

  my $url = $self->_url($self->config->{session_url}, %parms);
  my $response = $ua->get($url);
  my $session = {  %{ XMLin( $response->content ) }};
  #warn $response->content;
  unless ($self->session_id) {
    $self->{_session_id} = sha1_hex(time . $$ . $session->{user_id} . rand);
  }

  $session->{last_refresh} = time;

  $self->{_session} = $session;

  $self->_cache->set("session_" . $self->session_id,
		    $session,
		    "72 hours", 
		   );
}



sub session_id {
  my $self = shift;
  $self->{_session_id} || '';
}

sub user_id {
  shift->_session_field('user_id');
}

sub email {
  shift->_session_field('email');
}

sub username {
  shift->_session_field('username');
}

sub data_age {
  my $self = shift;
  my $last_refresh = $self->_session_field('last_refresh');
  return unless $last_refresh;
  return time - $last_refresh;
}

sub is_authenticated {
  my $self = shift;
  $self->user_id ? 1 : 0;
}

sub _session_field {
  my $self  = shift;
  my $field = shift;
  return '' unless $self->{_session};
  return $self->{_session}->{$field} || '';
}

sub login_url {
  my $self = shift;
  my %args = @_;
  my $url = $self->config->{login_url};

  my $info_request = delete $args{info_request};
  if ($info_request) { 
    # TODO: validate parameters?
    $info_request = join ",", @$info_request if ref $info_request eq "ARRAY";
    $args{i} = $info_request;
  }

  $self->_url($url, %args);
}

sub logout_url {
  my $self = shift;
  my $url = $self->config->{logout_url};
  $self->_url($url, @_);
}

sub _url {
  my $self = shift;
  my $url  = shift;
  my %args = @_;
  my $uconfig = delete $args{config} || $self->config; 
  my %query = (s => $uconfig->{site_id});
  $query{r} = delete $args{return_url} if $args{return_url};
  $query{f} = 'xml';
  $query{v} = $AUTH_VERSION;

  %query = (%args, %query);
  $query{sig} = $self->_calculate_signature(map { "$_=$query{$_}" } 
					    sort keys %query );

  my $query = join ";", map { "$_=" . uri_escape($query{$_}) } keys %query;
  $url .= "?$query";
  $url;
}

sub config {
  my $self = shift;
  if (($config->{last_refresh} || 0) + ($config->{config_cache_time} || 0)  < time) {
    $self->_fetch_config;
  } 
  $config;
}

sub _config_cache_key {
  my $self = shift;
  Carp::cluck("no  config base yet?!") unless $config_base;
  $config_cache_key .= join ":", $config_base->{site_id}, $config_base->{service};
}

sub _reset_config {
  my $class = shift;
  $class->_cache->remove($class->_config_cache_key) if $config_base;
  $config = undef;
  $config_base = undef;
  1;
}

sub _fetch_config {
  my $class = shift;
  $config = $class->_cache->get($class->_config_cache_key);
  return $config if $config;

  my $config_url = $class->_url($config_base->{service} . "/api/config", 
				config => $config_base
			       );

  my $response = $ua->get($config_url);

  if ($response->is_success) { 
    $config = {  %{ XMLin( $response->content ) } };
    $config->{last_refresh} = time;
    #warn $response->content;
    #use Data::Dumper;
    #warn Data::Dumper->Dump([\$config], [qw(config)]);
  }
  else {
    carp "Could not get config from auth service: " . $response->status_line;
    return 0;
  }

  $class->_save_config;
}

sub set_config {
  my $class = shift;
  my %args  = @_;
  my @keys = qw(service site_key site_id);
  defined $args{$_} or carp "required parameter $_ not set" and return for @keys;
  
  $config_base = {};  # be paranoid
  $config_base->{$_} = $args{$_} for @keys;

  $class->_fetch_config unless $config;
  $class->_save_config;

  return 1;
}

sub _save_config {
  my $class = shift;

  $config = { %$config, %$config_base };
  $class->_cache->set($class->_config_cache_key, $config, $config->{config_cache_time});

}

sub _calculate_signature {
  my $self = shift;
  my @keys = @_;
  my $now = time;
  my $key = join(";", $now, $config_base->{site_key}, @keys);
  #warn "KEY: [$key]";
  my $sig = sha1_hex($key);
  "$sig,$now";
}

sub _cache {
  $cache;
}

1;

__END__

=head1 NAME

Sau::Client - Client library for the Sau single sign-on service

=head1 SYNOPSIS

  Sau::Client->set_config(service  => 'http://g.develooper.com:8667/',
                          site_id  => 5,
                          site_key => '9cf205cc2d5df60b69246a8b58061a',
                         );

  my $auth = Sau::Client->new();
  $cgi->redirect($auth->login_url(return_url   => "http://my.site/path/",
                                  info_request => 'email',
                                 );
  
  # new request, user comes back from the auth service with a "t" parameter
  my $auth = Sau::Client->new(t => $r->param('t'));
  if ($auth->is_authenticated) {
    print "Hello ", $auth->username if $auth->username;
    ... # show stuff for logged in users
  }
  


=head1 METHODS

=over 4

=item set_config (service => $service_base_url, site_id => $our_id, site_key => $site_key)

Class method initializing the auth client.  You (currently) must call this
function at least once every 6 hours.

=item login_url (return_url => $url, info_request => $info_request)

Returns the login url on the auth service with the appropriate query string for your site.

=over 4

=item return_url

Specify the url the auth server will redirect to after a successful
login.  It must be within the domain specified in the site setup.

=item info_request

By default the only information the auth server provides about the
user is an ID number and a site session id.  Both are unique to your
site and can not be correlated to IDs on other sites.  (This
implementation doesn't expose the "site session id" in the interface).

The info request parameter takes either a comma separated string or an
array ref, for example "username" or ['email','username'].

Valid parameters are currently C<email> and C<username>.

The user will get shown an options page and must explicitly allow the
auth server to pass the information.  If the user allow the
information to be passed, this preference will be remembered for the
future.

Take note that this means you might get returned an authenticated user
that is not giving the site the requested information.  If the
information is required for your site to function you can explain that
to the user and direct them back to the login_url.

=back

=item logout_url (return_url => $return_url)

As login_url, but only supports the return_url parameter.

=item new (ticket => $ticket OR session_id => $session_id)

Create a new auth object.

The auth server will include a "t" parameter in the query string in
the return url after the user logs in.  This is a one time "ticket"
Sau::Client uses to create a new session.  You must call the
session_id method to get the session id and store it in a cookie and
then use that on subsequent requests from the same user.

=item delete_session 

Deletes the current session.  Must be called when the "logout url" is
requested.

=item is_authenticated

Returns true if we have a valid session with a logged in user.

=item session_id

Returns the session_id for the current session.  If you created a new
session with a "ticket" you MUST set a cookie and use that to
reference the session again.

=item user_id

Returns the numerical id of the user.  The id is specific to your
site.

=item email

If requested (and the user allowed) returns the primary email address of the user.

=item username

If requested (and the user allowed) returns the username of the user.

=item data_age

Returns the number of seconds since the session data was last refreshed from the auth server.

=item force_refresh($seconds)

Force a refresh of the session data if the cached data is older than $seconds.

=item config

Returns a hashref with the current configuration.  (This method should
not usually be used unless you are subclassing the module).

=back 

=head1 TODO

Create session_ids that can be decrypted back to a site_session so we
can expire the cache without having users lose their session with the
site.

Allow use of something else than Cache::FileCache for the session cache.

Allow configuration of the Cache:: module

Add the "force" ("f") parameter to the login_url parameters (and
documentation)

=head1 AUTHOR

Copyright 2004 Ask Bjoern Hansen, Develooper LLC (ask@develooper.com)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   L<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.



package Test::AuthClient;
use strict;

sub config_args {
  return (service  => 'http://logindev.perl.org/',
	  site_id  => 1,
	  site_key => '05d36ab2961aef502f2c62f0854549',
  );
 }

1;

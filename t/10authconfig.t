use Test::More tests => 10;
use lib 't';
use Test::AuthClient;

use_ok('Sau::Client', 'load module');

ok(Sau::Client->_reset_config(), 'reset config');
ok(Sau::Client->set_config(Test::AuthClient->config_args), 'set config');
ok(my $auth = Sau::Client->new(), "new");
ok($auth->login_url, "get login_url");
ok(!$auth->is_authenticated, "is not authenticated");
ok(!$auth->username, "no username"); 

is($auth->config->{site_id}, 1, "config->{site_id}");

ok(Sau::Client->set_config(Test::AuthClient->config_args), 'set config (now cached)');

is($auth->config->{site_id}, 1, "config->{site_id} - after set_config");

# TODO: check that the authclient is caching the config properly?



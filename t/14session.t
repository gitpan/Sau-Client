use Test::More qw(no_plan);
use strict;
use warnings;
use lib 't';
use_ok('Sau::Client');
use Test::AuthClient;

# For now just testing non-working sessions here, the real session tests are in 12tickets.t

ok(Sau::Client->set_config(Test::AuthClient->config_args), 'set config');

ok(my $auth = Sau::Client->new(session_id => "1234"), "new authclient, with non existing session_id");
ok(!$auth->is_authenticated, "isn't authenticated");
is($auth->username, "", "no session, no user_id"); 
is($auth->session_id, "", "invalid session_id makes auth->session_id return emptry string");


ok($auth = Sau::Client->new(session_id => '44574810595a34b3c7dd5ba602a2366bea9166f3'), 'foo');
 


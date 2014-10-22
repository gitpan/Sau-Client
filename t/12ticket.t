use Test::More qw(no_plan);
use strict;
use warnings;
use lib 't';
use_ok('Sau::Client');
use Test::AuthClient;
use Test::WWW::Mechanize;

my $agent = Test::WWW::Mechanize->new();

ok(Sau::Client->set_config(Test::AuthClient->config_args), 'set config');

ok(my $auth = Sau::Client->new(), "new");

$agent->get($auth->login_url);
ok($agent->success, "got login page");
$agent->set_visible('test', 'foo');
$agent->click;

my %q = URI::URL->new($agent->uri)->query_form;
ok($q{t}, "got ticket");

# simulate new request to the site server ...

ok($auth = Sau::Client->new(ticket => $q{t}), "new authclient, with ticket");
ok($auth->is_authenticated, "is_authenticated");
ok($auth->user_id, "user_id"); 
is($auth->username, "test", "username"); 
ok($auth->email, "email");
ok(my $session_id = $auth->session_id, "get session_id");

# new request with the session_id
ok($auth = Sau::Client->new(session_id => $session_id), "new authclient, with session_id");
is($auth->username, "test", "username is still test with session_id"); 

ok(sleep 2, "sleep 2 seconds");
ok($auth->data_age >= 2, "data_age 2 seconds or older");

ok($auth->force_refresh(1), "force_refresh");
ok($auth->data_age < 2, "data_age less than 2 seconds");

ok($auth->delete_session, "delete session");
is($auth->data_age, undef, "data_age undef without a session");

my $return_url = "http://authtest.askask.com/?test=logout";
$agent->get($auth->logout_url("return_url" => $return_url));
ok($agent->success, 'got logout page');
$agent->follow_link( text_regex => qr/Continue/i );
is($agent->uri, $return_url, "landed at the right page"); 



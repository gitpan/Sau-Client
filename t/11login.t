use Test::More tests => 12;
use strict;
use warnings;
use lib 't';
use_ok('Sau::Client');
use Test::AuthClient;
use Test::WWW::Mechanize;

ok(Sau::Client->set_config(Test::AuthClient->config_args), 'set config');

ok(my $auth = Sau::Client->new(), "new");

my $agent = Test::WWW::Mechanize->new();
$agent->get($auth->login_url);
ok($agent->success, "got login page");
$agent->form_name('login');
$agent->field('login', 'test');
$agent->field('password', 'foo');
$agent->click;
my $uri = URI::URL->new($agent->uri);

is($uri->host, "authtest.askask.com", "we got sent to authtest");

#if(open F, ">/home/ask/public_html/tmp/a1.html") {
#  print F $agent->content;
#  close F;
#}

my (%q) = $uri->query_form;
ok($q{t}, "got ticket");
ok($auth = Sau::Client->new(t => $q{t}), "new authclient, with ticket");
ok($auth->delete_session, "delete session right away");

my $return_url = "http://authtest.askask.com/?test=logout";
$agent->get($auth->logout_url("return_url" => $return_url));
$agent->follow_link( text_regex => qr/Continue/i );
ok($agent->success, 'got logout page');
is($agent->uri, $return_url, "landed at the right page"); 

my $url = $auth->login_url(info_request => "email");
like($url, qr/i=email/, 'login_url(info_request => "email")'); 
$url = $auth->login_url(info_request => ['username','email']);
like($url, qr/i=username(,|\%2C)email/, 'login_url(info_request => [array])'); 



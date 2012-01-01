#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 3;
require_ok("RateLimitServer");

subtest "request id" => sub {
	plan tests => 8;

	my $req = "ping";
	my $ans = "pong";

	is RateLimitServer::process_request($req), $ans, "request without an id";
	is RateLimitServer::process_request("27823 $req"), "27823 $ans", "request with an id";
	is RateLimitServer::process_request("000867465 $req"), "000867465 $ans", "request with an id starting with zero";
	is RateLimitServer::process_request("394769760968709384567 $req"), "394769760968709384567 $ans", "request with a large id";

	# Bad requests (ones that elicit no response) should always elicit no
	# response, even if a request ID was given
	$req = "no_such_command";
	$ans = undef;
	is RateLimitServer::process_request($req), $ans, "bad request without an id";
	is RateLimitServer::process_request("27823 $req"), $ans, "bad request with an id";
	is RateLimitServer::process_request("000867465 $req"), $ans, "bad request with an id starting with zero";
	is RateLimitServer::process_request("394769760968709384567 $req"), $ans, "bad request with a large id";
};

subtest "fussiness" => sub {
	plan tests => 6;

	is RateLimitServer::process_request("ping"), "pong", "ping";
	is RateLimitServer::process_request("PING"), undef, "requests are case-sensitive";
	is RateLimitServer::process_request(" ping"), undef, "requests are sensitive to leading space";
	is RateLimitServer::process_request("ping "), undef, "requests are sensitive to trailing space";

	is RateLimitServer::process_request("123 ping"), "123 pong", "ping with id";
	is RateLimitServer::process_request("123  ping"), undef, "request id is sensitive to whitespace";
};

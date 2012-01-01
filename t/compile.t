#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 5;
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

# We'll be overriding things in the RateLimitServer package
no warnings qw( redefine once );
our $t;
local *RateLimitServer::now = sub { $t };

subtest "basic strict limit" => sub {
	plan tests => 401;

	my $key = "ws ip=193.195.43.199";
	$t = time();

	# 22 requests in 20 seconds, strict.

	# Send 300 requests 1 second apart: they should all succeed
	for (1..300) {
		my $resp = RateLimitServer::process_request("over_limit $key");
		like $resp, qr/^ok N /, "under limit $_ of 300";
		note $resp;
		$t += 1;
	}

	# Now send 100 requests in 10 seconds, to force us over the limit
	# The first few will succeed, the rest will fail
	for (1..100) {
		my $resp = RateLimitServer::process_request("over_limit $key");
		if ($_ <= 3) {
			like $resp, qr/^ok N /, "under limit $_ of 300";
		} else {
			like $resp, qr/^ok Y /, "over limit $_ of 300";
		}
		note $resp;
		$t += 0.1;
	}

	like RateLimitServer::process_request("get_size"), qr{^size=1/\d+ keys=1$}, "size with 1 key";
};

subtest "basic leaky limit" => sub {
	plan tests => 202;

	my $key = "ws ua=libvlc";
	$t = time();

	# 125 requests in 10 seconds, strict.

	# Send 200 requests over 20 seconds: they should all succeed
	for (1..200) {
		my $resp = RateLimitServer::process_request("over_limit $key");
		like $resp, qr/^ok N /, "under limit $_ of 300";
		note $resp;
		$t += 0.1;
	}

	# Now send 200 requests over 10 seconds.
	# Some will succeed, some will fail.
	# (Specifically the first few all succeed, then it's a mix of success and
	# failure - but FIXME we don't test this detail, just the final count).
	my $over = 0;
	for (1..200) {
		my $resp = RateLimitServer::process_request("over_limit $key");
		++$over if $resp =~ m/^ok Y /;
		note $resp;
		$t += 0.05;
	}
	is $over, 44, "44 of 200 were over the limit";

	like RateLimitServer::process_request("get_size"), qr{^size=\d+/\d+ keys=2$}, "size with 2 keys";
};


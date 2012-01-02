#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 6;
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
	plan tests => 400;

	my $key = "dummy";
	$t = time();

	local *RateLimitServer::find_ratelimit_params = sub {
		$_[0] eq $key or die "unexpected key @_";
	    # ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);
		return (undef, undef, 22, 20, 1, $key, 0);
	};

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
};

subtest "basic leaky limit" => sub {
	plan tests => 202;

	my $key = "dummy";
	$t = time();

	local *RateLimitServer::find_ratelimit_params = sub {
		$_[0] eq $key or die "unexpected key @_";
	    # ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);
		return (undef, undef, 125, 10, 0, $key, 0);
	};

	# 125 requests in 10 seconds, leaky.

	# Send 200 requests over 20 seconds: they should all succeed
	for (1..200) {
		my $resp = RateLimitServer::process_request("over_limit $key");
		like $resp, qr/^ok N /, "under limit $_ of 300";
		note $resp;
		$t += 0.1;
	}

	# Now send 200 requests over 10 seconds.
	# Some will succeed, some will fail.
	my @responses;
	for (1..200) {
		my $resp = RateLimitServer::process_request("over_limit $key");
		push @responses, $resp;
		note $resp;
		$t += 0.05;
	}
	# Specifically the first few all succeed, then it's a mix of success and
	# failure
	my $n1 = grep /^ok N /, @responses[0..29];
	is $n1, 30, "first 30 responses all succeed";
	my $n2 = grep /^ok N /, @responses[-10..-1];
	is $n2, 6, "6/10 last responses succeed";
};

subtest "get_size" => sub {
	plan tests => 2;

	local %RateLimitServer::hash = ();

	like RateLimitServer::process_request("get_size"), qr/^size=\S+ keys=0$/, "starts off empty";

	RateLimitServer::do_ratelimit(10, 10, "key 1", 1, 0);
	RateLimitServer::do_ratelimit(10, 10, "key 1", 1, 0);
	RateLimitServer::do_ratelimit(10, 10, "key 3", 1, 0);
	RateLimitServer::do_ratelimit(10, 10, "key 2", 1, 0);

	like RateLimitServer::process_request("get_size"), qr/^size=\S+ keys=3$/, "after 3 keys";
};

# TODO, "generic" things to test:
# keep_stats / get_stats

# TODO, "custom" things to test:
# request munging


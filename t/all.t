#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 8;

require_ok("RateLimitServer");

my $t = time;
{
	package MyRLS;
	use base qw/ RateLimitServer /;
	sub now { $t }
}

subtest "request id" => sub {
	plan tests => 8;

	my $rls = RateLimitServer->new;
	my $req = "ping";
	my $ans = "pong";

	is $rls->process_request($req), $ans, "request without an id";
	is $rls->process_request("27823 $req"), "27823 $ans", "request with an id";
	is $rls->process_request("000867465 $req"), "000867465 $ans", "request with an id starting with zero";
	is $rls->process_request("394769760968709384567 $req"), "394769760968709384567 $ans", "request with a large id";

	# Bad requests (ones that elicit no response) should always elicit no
	# response, even if a request ID was given
	$req = "no_such_command";
	$ans = undef;
	is $rls->process_request($req), $ans, "bad request without an id";
	is $rls->process_request("27823 $req"), $ans, "bad request with an id";
	is $rls->process_request("000867465 $req"), $ans, "bad request with an id starting with zero";
	is $rls->process_request("394769760968709384567 $req"), $ans, "bad request with a large id";
};

subtest "fussiness" => sub {
	plan tests => 6;

	my $rls = RateLimitServer->new;

	is $rls->process_request("ping"), "pong", "ping";
	is $rls->process_request("PING"), undef, "requests are case-sensitive";
	is $rls->process_request(" ping"), undef, "requests are sensitive to leading space";
	is $rls->process_request("ping "), undef, "requests are sensitive to trailing space";

	is $rls->process_request("123 ping"), "123 pong", "ping with id";
	is $rls->process_request("123  ping"), undef, "request id is sensitive to whitespace";
};

subtest "basic strict limit" => sub {
	plan tests => 400;

	our $key = "dummy";

	{
		package MyRLSBasicStrict;
		use base qw/ MyRLS /;
		sub find_ratelimit_params {
			my ($self, $k) = @_;
			$k eq $key or die "unexpected key $k not $key";
			# ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);
			return (undef, undef, 22, 20, 1, $key, 0);
		}
	}

	my $rls = MyRLSBasicStrict->new;

	# 22 requests in 20 seconds, strict.

	# Send 300 requests 1 second apart: they should all succeed
	for (1..300) {
		my $resp = $rls->process_request("over_limit $key");
		like $resp, qr/^ok N /, "under limit $_ of 300";
		note $resp;
		$t += 1;
	}

	# Now send 100 requests in 10 seconds, to force us over the limit
	# The first few will succeed, the rest will fail
	for (1..100) {
		my $resp = $rls->process_request("over_limit $key");
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

	our $key = "dummy";

	{
		package MyRLSBasicLeaky;
		use base qw/ MyRLS /;
		sub find_ratelimit_params {
			my ($self, $k) = @_;
			$k eq $key or die "unexpected key $k not $key";
			# ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);
			return (undef, undef, 125, 10, 0, $key, 0);
		}
	}

	my $rls = MyRLSBasicLeaky->new;

	# 125 requests in 10 seconds, leaky.

	# Send 200 requests over 20 seconds: they should all succeed
	for (1..200) {
		my $resp = $rls->process_request("over_limit $key");
		like $resp, qr/^ok N /, "under limit $_ of 300";
		note $resp;
		$t += 0.1;
	}

	# Now send 200 requests over 10 seconds.
	# Some will succeed, some will fail.
	my @responses;
	for (1..200) {
		my $resp = $rls->process_request("over_limit $key");
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

	my $rls = RateLimitServer->new;

	like $rls->process_request("get_size"), qr/^size=\S+ keys=0$/, "starts off empty";

	$rls->do_ratelimit(10, 10, "key 1", 1, 0);
	$rls->do_ratelimit(10, 10, "key 1", 1, 0);
	$rls->do_ratelimit(10, 10, "key 3", 1, 0);
	$rls->do_ratelimit(10, 10, "key 2", 1, 0);

	like $rls->process_request("get_size"), qr/^size=\S+ keys=3$/, "after 3 keys";
};

subtest "stats" => sub {
	plan tests => 3;

	{
		package MyRLSStats;
		use base qw/ RateLimitServer /;
		sub find_ratelimit_params {
			my ($self, $key) = @_;
			# ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);

			return (undef, undef, 10, 1, 1, "key_without_stats")
				if $key eq "key_without_stats";

			return (undef, undef, 10, 1, 1, "key_with_stats", 1)
				if $key eq "key_with_stats";

			die "unexpected key";
		}
	}

	my $rls = MyRLSStats->new;

	is $rls->process_request("get_stats not_seen_yet"),
		"n_req=0 n_over=0 last_max_rate=0 key=not_seen_yet",
		"not_seen_yet";

	for (1..20) {
		note $rls->process_request("over_limit key_without_stats");
		note $rls->process_request("over_limit key_with_stats");
	}

	is $rls->process_request("get_stats key_without_stats"),
		"n_req=0 n_over=0 last_max_rate=0 key=key_without_stats",
		"stats for a key where we don't keep stats";

	is $rls->process_request("get_stats key_with_stats"),
		"n_req=20 n_over=9 last_max_rate=0 key=key_with_stats",
		"stats for a key where we do keep stats";
};

subtest "buckets" => sub {
	plan tests => 6;

	# last_max_rate is for previous bucket, other stats are cumulative

	$t = int time();
	$t -= ($t % 300);
	++$t;
	local $SIG{ALRM} = $SIG{ALRM};

	{
		package MyRLSBuckets;
		use base qw/ MyRLS /;
		sub find_ratelimit_params {
			my ($self, $key) = @_;
			# ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);
			return (undef, undef, 22, 20, 0, $key, 1);
		}
	}

	my $rls = MyRLSBuckets->new;

	# bucket #1
	$rls->check_next_bucket();

	for (1..50) {
		$t += 0.5;
		note $rls->process_request("over_limit one");
		$t += 0.5;
		note $rls->process_request("over_limit one");
		note $rls->process_request("over_limit two");
	}
	$t += 250;

	is $rls->process_request("get_stats one"), "n_req=100 n_over=31 last_max_rate=0 key=one", "bucket #1 key one";
	is $rls->process_request("get_stats two"), "n_req=50 n_over=0 last_max_rate=0 key=two", "bucket #1 key two";

	# bucket #2
	$rls->check_next_bucket();

	for (1..100) {
		$t += 0.25;
		note $rls->process_request("over_limit one");
		$t += 0.25;
		note $rls->process_request("over_limit one");
		note $rls->process_request("over_limit two");
	}
	$t += 250;

	# last_max_rate is for previous bucket, other stats are for this bucket
	is $rls->process_request("get_stats one"), "n_req=300 n_over=158 last_max_rate=22 key=one", "bucket #2 key one";
	is $rls->process_request("get_stats two"), "n_req=150 n_over=31 last_max_rate=18 key=two", "bucket #2 key two";

	# bucket #3
	$rls->check_next_bucket();

	is $rls->process_request("get_stats one"), "n_req=300 n_over=158 last_max_rate=22 key=one", "bucket #3 key one";
	is $rls->process_request("get_stats two"), "n_req=150 n_over=31 last_max_rate=22 key=two", "bucket #3 key two";
};

# TODO, test request munging - should use new key for test & stats


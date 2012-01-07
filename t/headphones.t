#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More 0.94; # need subtest
use Test::More tests => 2;

require_ok("RateLimitServer");

my $t = time;
{
	package MyRLS;
	use base qw/ RateLimitServer /;
	sub now { $t }
}

subtest "headphones stats only" => sub {
	plan tests => 101;

	my $rls = MyRLS->new;

	for (1..100) {
		like $rls->process_request("over_limit ws ua=python-headphones/0.7.3"),
			qr/^ok N 0/, "not over limit, rate=0";
	}

	my $s = $rls->get_stats("ws ua=python-headphones/0.7.3");
	note $s;
	is $s, "n_req=100 n_over=0 last_max_rate=0 key=ws ua=python-headphones/0.7.3", "has 100 requests";
};


#!/usr/bin/perl
# vi: set ts=4 sw=4 :
#____________________________________________________________________________
#
#   MusicBrainz -- the open internet music database
#
#   Copyright (C) 1998 Robert Kaye
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#	This script originally by Dave Evans.
#____________________________________________________________________________

use warnings;
use strict;
use integer;

=pod

There is no hash size management (auto-deletion of expired data) in this
server.  I suggest you run this with an appropriate memory limit, and set
it to respawn when it runs out of memory and terminates.

Also note that there is NO SECURITY built into this system (e.g. this server
neither knows nor cares who is making the requests) - which is why its use is
disabled by default.

=cut

package RateLimitServer;

use Time::HiRes qw( time );
sub now { time() }

our $verbose;

sub run
{
	@_ == 2 or die "Usage: $0 ADDR PORT\n";
	my ($addr, $port) = @_;

	local $verbose = $ENV{VERBOSE};

	use IO::Socket::INET;
	my $sock = IO::Socket::INET->new(
		Proto => 'udp',
		LocalPort => $port,
		LocalAddr => $addr,
	) or die $!;

	my $stop = 0;
	$SIG{TERM} = sub { $stop = 1 };
	$SIG{INT} = $SIG{TERM} if -t;

	$| = 1;
	print "starting\n";

	check_next_bucket();

	for (;;)
	{
		last if $stop;

		my $request;
		my $peer = recv($sock, $request, 1000, 0);
		if (not defined $peer)
		{
			next if $!{EINTR};
			die "recv: $!";
		}

		print ">> $request\n"
			if $verbose;
		my $reply = process_request($request, $peer);
		if (not defined $reply)
		{
			print "no reply (>> $request)\n";
			next;
		}
		print "<< $reply (>> $request)\n";

		my $r = send($sock, $reply, 0, $peer);
		defined($r) or die "send: $!";
	}

	print "exiting\n";
}

sub process_request
{
	my ($request, $peer) = @_;

	my $id;
	if ($request =~ /\A(\d+) (.*)/s)
	{
		$id = $1;
		$request = $2;
	}

	my $response = process_request_2($request, $peer);

	$response = "$id $response" if defined($response) and defined($id);

	return $response;
}

sub process_request_2
{
	my ($request, $peer) = @_;

	if ($request =~ /^over_limit (.*)$/)
	{
		return over_limit($1);
	}
	elsif ($request =~ /^get_stats (.*)$/)
	{
		return get_stats($1);
	}
	elsif ($request eq "get_size")
	{
		return get_size();
	}
	elsif ($request eq "ping")
	{
		return "pong";
	}

	return undef;
}

sub over_limit
{
	my ($key) = @_;

	my ($over_limit, $rate, $limit, $period, $strict, $new_key, $keep_stats) = find_ratelimit_params($key);

	($over_limit, $rate) = do_ratelimit($limit, $period, $key, 1, $strict)
		if not defined $over_limit;

	keep_stats($limit, $period, $key, $over_limit, $rate)
		if $keep_stats;

	return sprintf "ok %s %.1f %.1f %d",
		($over_limit ? "Y" : "N"), $rate, $limit, $period;
}

sub find_ratelimit_params
{
	my ($key) = @_;

	# The server - that's us - gets to decide what limits to impose for
	# each key.  The idea is that this makes it easier to adjust the
	# limits on the fly - simply tweak this script and restart it.

	$key =~ s/\bip=(132\.185\.\d+\.\d+)\b/cust=bbc/;
	$key =~ s/\bip=(212\.58\.2[2-5]\d\.\d+)\b/cust=bbc/;

	$key =~ s{ ua=([ -]*|((Java|Python-urllib|Jakarta Commons-HttpClient)/[0-9._]+))$}{ ua=generic-bad-ua}
		unless $key =~ m{\Q ua=python-musicbrainz/0.7.3\E};

	my ($over_limit, $rate, $limit, $period, $strict, $keep_stats);

	{
		#############################
		# Per-user limits: strict
		#############################

		# MBH-146 Give the BBC a high ratelimit
		($limit, $period, $strict) = (15*20, 20, 0), last
			if $key =~ /^(.*) cust=bbc$/;

		# MusicBrainz::Server::Mason
		($limit, $period, $strict) = (22, 20, 1), last
			if $key =~ /^mason ip=(\d+\.\d+\.\d+\.\d+)$/;

		# MusicBrainz::Server::Handlers::WS::1::Common
		($limit, $period, $strict) = (22, 20, 1), last
			if $key =~ /^ws ip=(\d+\.\d+\.\d+\.\d+)$/;

		# Old web service (cgi-bin/*.pl)
		($limit, $period, $strict) = (10, 30, 1), last
			if $key =~ m{^/mm-2.1/Find\w+ ip=(\d+\.\d+\.\d+\.\d+)$};
		($limit, $period, $strict) = (22, 20, 1), last
			if $key =~ m{^/mm-2.1/\w+ ip=(\d+\.\d+\.\d+\.\d+)$};

		# Public search server
		($limit, $period, $strict) = (22, 20, 1), last
			if $key =~ /^search ip=(\d+\.\d+\.\d+\.\d+)$/;

		#############################
		# Shared limits: not strict
		#############################

		$keep_stats = 1;

		# MusicBrainz::Server::Handlers::WS::1::Common
		($limit, $period, $strict) = (3000, 10, 0), last
			if $key =~ /^ws global$/;

		($limit, $period, $strict) = (30, 30, 0), last
			if $key =~ m{^/mm-2.1/Find\w+ global$};
		($limit, $period, $strict) = (100, 10, 0), last
			if $key =~ m{^/mm-2.1/\w+ global$};

		# Bad user-agents
		($limit, $period, $strict) = (500, 10, 0), last
			if $key eq "ws ua=python-musicbrainz/0.7.3";
		($limit, $period, $strict) = (500, 10, 0), last
			if $key eq "ws ua=generic-bad-ua";

		# VLC -- was 100, 30
		($limit, $period, $strict) = (125, 10, 0), last
			if $key =~ /^ws ua=(libvlc)$/;
		($limit, $period, $strict) = (125, 10, 0), last
			if $key =~ /^ws ua=(nsplayer)$/;
		# No UA
		($limit, $period, $strict) = (500, 10, 0), last
			if $key =~ /^ws ua=-$/;

		# Default is to allow everything
		print "Warning: using default key for >> over_limit $_[0]\n";
		$key = "default";
		($over_limit, $rate, $limit, $period) = (0, 0, 1, 1);
	}

	return ($over_limit, $rate, $limit, $period, $strict, $key, $keep_stats);
}

use Carp qw( croak );

# At the moment the data store is all in memory, though this could easily be
# changed to something DBM-ish if that proves necessary.
our %hash;

sub get_size
{
	sprintf "size=%s keys=%d", scalar(%hash), scalar(keys %hash);
}

# Idea and logic stolen from exim4 (acl.c, acl_ratelimit)
sub do_ratelimit
{
	my ($limit, $period, $key, $use, $strict) = @_;
	$use = 1 if not defined $use;
	$period > 0 or croak "Bad period";

	printf "ratelimit condition limit=%.0f period=%.0f key=%s\n",
		$limit, $period, $key,
		if $verbose;

	no integer;
	my $now = now();

	my $dbd_time;
	my $dbd_rate;
	my $data;

	if (not($data = $hash{$key}))
	{
		printf "ratelimit initializing new key's data\n"
			if $verbose;

		$data = $hash{$key} = [ $now, 0 ];
		$dbd_time = $now;
		$dbd_rate = 0;
	}
	else
	{
		($dbd_time, $dbd_rate) = @$data;

		my $interval = $now - $dbd_time;
		$interval = 1E-9 if $interval <= 0;

		my $i_over_p = $interval / $period;
		my $a = exp(-$i_over_p);

		$dbd_time = $now;
		$dbd_rate = $use * (1 - $a) / $i_over_p + $a * $dbd_rate;
	}

	my $over_limit = ($dbd_rate >= $limit);

	if (not $over_limit or $strict)
	{
		$data->[0] = $dbd_time;
		$data->[1] = $dbd_rate;
	}

	printf "ratelimit computed rate=%s key=%s\n", $dbd_rate, $key
		if $verbose;

	return(wantarray ? ($over_limit, $dbd_rate) : $over_limit);
}

{
	my %n_req;
	my %n_over;
	my %max_rate;
	my %last_max_rate;

	sub keep_stats
	{
		my ($limit, $period, $key, $over_limit, $rate) = @_;
		++$n_req{$key};
		++$n_over{$key} if $over_limit;
		$max_rate{$key} = $rate
			if $rate > ($max_rate{$key}||0);
	}

	sub get_stats
	{
		my ($key) = @_;
		my $n_req = $n_req{$key} || 0;
		my $n_over = $n_over{$key} || 0;
		sprintf "n_req=%d n_over=%d last_max_rate=%d key=%s",
			$n_req, $n_over, $last_max_rate{$key}||0, $key;
	}

	sub clear_max_rate
	{
		%last_max_rate = %max_rate;
		%max_rate = ();
	}
}

{
	my $next_bucket;

	sub check_next_bucket
	{
		my $now = now();
		if (not $next_bucket or $now >= $next_bucket)
		{
			clear_max_rate();
			$next_bucket = $now + 300;
			$next_bucket -= ($next_bucket % 300);
			$SIG{ALRM} = \&check_next_bucket;
			my $in = ($next_bucket - $now);
			print "new bucket started, will check again in $in sec\n";
			alarm(($in > 1) ? $in : 1);
		}
	}
}

run(@ARGV) unless caller;

1;
# eof RateLimitServer.pm

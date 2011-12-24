#!/usr/bin/perl
# vi: set ts=4 sw=4 :
#____________________________________________________________________________
#
#   MusicBrainz -- the open internet music database
#
#   Copyright (C) 2000 Robert Kaye
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
#   This module by Dave Evans, July 2007.
#____________________________________________________________________________

use warnings;
use strict;

=pod

	use MusicBrainz::Server::RateLimitClient;

	$query = "get_size";
	$server = "127.0.0.1:2000";
	$response = MusicBrainz::Server::RateLimitClient->query($query, $server);

	die "something went wrong" if not defined $response;
	print "Response: $response\n";

=cut

package MusicBrainz::Server::RateLimitClient;

require IO::Socket::INET;

{
	my $last_server = '';
	my $last_socket;

	sub get_socket
	{
		my ($class, $server) = @_;
		return $last_socket
			if $server eq $last_server
			and $last_socket;
		close $last_socket if $last_socket;

		$last_server = $server;
		$last_socket = IO::Socket::INET->new(
			Proto		=> 'udp',
			PeerAddr	=> $server,
		);
	}

	sub force_close
	{
		close $last_socket if $last_socket;
		$last_socket = undef;
	}
}

our $id = 0;

sub query
{
	my ($class, $query, $server) = @_;

	defined($server) or return undef;
	my $sock = $class->get_socket($server);

	{ use integer; ++$id; $id &= 0xFFFF }

	my $request = "$id $query";
	my $r;

	$r = send($sock, $request, 0);
	if (not defined $r)
	{
		# Send error
		return undef;
	}

	my $rv = '';
	vec($rv, fileno($sock), 1) = 1;
	select($rv, undef, undef, 0.5);

	if (not vec($rv, fileno($sock), 1))
	{
		# Timeout
		return undef;
	}

	my $data;
	$r = recv($sock, $data, 1000, 0);
	if (not defined $r)
	{
		# Receive error
		return undef;
	}

	unless ($data =~ s/\A($id) //)
	{
		force_close();
		return undef;
	}

	return $data;
}

1;
# eof RateLimitClient.pm

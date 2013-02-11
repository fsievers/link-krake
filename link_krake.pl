#!/usr/bin/env perl
#
package link_krake;

use strict;
use warnings;
use Data::Dumper;

use URI;
use URL::Normalize;
use HTML::SimpleLinkExtor;
use LWP::UserAgent;
use DBI;

my $ua = LWP::UserAgent->new(agent => "SLK - Schöne Link Krake");
$ua->timeout( 10 );

my $dbh = DBI->connect( "DBI:Pg:host=localhost;db=linkkrake",
	"username", "password", { AutoCommit => 1, PrintError => 0, RaiseError => 0 } );

my $MAXCHILDS = 20;
my $childs = 0;
my $sth    = $dbh->prepare( "SELECT id, url FROM URLs WHERE scanned != 1 ORDER BY RANDOM() LIMIT 200" );
my $rv     = $sth->execute;
while ( $rv ) {
	my $maxchilds;

	if( $rv < $MAXCHILDS) {
		$maxchilds = $rv;
	} else {
		$maxchilds = $MAXCHILDS;
	}
	#print "Max: $maxchilds\n";
	
	for ( 1 .. $rv ) {
		if ( $childs == $maxchilds ) {
			my $pid = wait;
			$childs--;
		}

		my $row = $sth->fetchrow_hashref;
		my $pid = fork();
		if ( $pid ) {

			# Parent
			$childs++;
		}
		elsif ( $pid == 0 ) {

			# Child
			query_for_links( $dbh, $row );
			exit 0;
		}

	}

	$sth = $dbh->prepare( "SELECT id, url FROM URLs WHERE scanned != 1 ORDER BY RANDOM() LIMIT 200" );
	$rv  = $sth->execute;
}

sub query_for_links {
	my ( $dbh, $row ) = @_;
	my $sth;
	my $url       = $row->{url};
	my $child_dbh = $dbh->clone;
	$dbh->{InactiveDestroy} = 1;
	$dbh = undef;

	local $SIG{ALRM} = sub { die "Connection Timeout" };

	alarm( 30 );
	my $head_response = $ua->head( $url );
	alarm( 0 );

#if ( $url =~ /([^\s]+(\.(?i)(pdf|ico|svg|css|js|javascript|java|jpg|jpeg|png|gif|bmp|avi|mpeg|mpg|mp4|mp3|mp2|xbm|flash))$)/ )
	if ( $head_response->is_success && $head_response->content_type ne 'text/html' ) {
		$sth = $child_dbh->prepare( "UPDATE URLs SET scanned = 1, last_scan = NOW() WHERE id = ?" );
		$sth->execute( $row->{id} );
		return;
	}

	if ( !$head_response->is_success ) {
		$sth = $child_dbh->prepare(
			"UPDATE URLs SET scanned = 1, last_scan = NOW(), errors = 1, last_error = NOW() WHERE id = ?" );
		$sth->execute( $row->{id} );
		print "Error: $url\n";
		return;
	}

	alarm( 30 );    # Define a hard timeout for crawling
	#print "\n$url";
	my $response = $ua->get( $url ) or next;    #die "Could not get '$url'";
	alarm( 0 );

	unless ( $response->is_success ) {

		#die $response->status_line;
		alarm( 0 );
		return;
	}

	my $html      = $response->decoded_content;
	my $extractor = HTML::SimpleLinkExtor->new;

	$extractor->parse( $html );

	my @links = $extractor->links;

	unless ( @links ) {
		print "No links found for $url\n";
		$sth = $child_dbh->prepare( "UPDATE URLs SET scanned = 1, last_scan = NOW() WHERE id = ?" );
		$sth->execute( $row->{id} );
		return;

		#exit;
	}
	else {
		for my $link ( sort @links ) {
			$link = URI->new_abs( $link, $url )
				unless ( URI->new( $link )->scheme );
			$link =~ s/(.*)#(.*)/$1/;
			$link = URI->new( $link )->canonical;

			if ( URI->new( $link )->scheme =~ /^https?/ ) {
				my $normalizer = URL::Normalize->new( url => $link );
				$normalizer->do_all;
				$link = $normalizer->get_url;
			}
			next if URI->new( $link )->eq($url);

			#print "$link\n" if (URI->new($link)->scheme =~ /^https?/);
			$sth = $child_dbh->prepare( "INSERT INTO URLs (url, scanned) VALUES(?, 0)" );
			$sth->execute( $link ) if ( URI->new( $link )->scheme =~ /^https?/ );
		}
		print $url . " - " . @links . "\n";
	}
	$sth = $child_dbh->prepare( "UPDATE URLs SET scanned = 1, last_scan = NOW() WHERE id = ?" );
	$sth->execute( $row->{id} );
}

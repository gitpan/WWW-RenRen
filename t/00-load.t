#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'WWW::RenRen' ) || print "Bail out!\n";
}

diag( "Testing WWW::RenRen $WWW::RenRen::VERSION, Perl $], $^X" );

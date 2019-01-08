# Copyright (c) 2019, cPanel, LLC.
# All rights reserved.
# http://cpanel.net
#
# This is free software; you can redistribute it and/or modify it under the
# same terms as Perl itself. See L<perlartistic>.

package Test::MockFileSys;

use strict;
use warnings;

use Carp ();

use Test::MockFile qw/filesys/;

my $fs; # This is the singleton for this package;

# Assure $fs is cleaned up before global destruction.
END {
    #clear all the keys.
    if($fs && ref $fs) {
        foreach my $key (keys %$fs) {
            delete $fs->{$key};
        }
    }
    
    # Remove our blessing of $fs.
    undef $fs;
}

sub _unmocked_file_access_hook;

sub new {
    $fs && return $fs;

    my ($class, @args) = @_;
    
    scalar @args % 2 and die("HASH not passed to new in " . __PACKAGE__);
    
    $fs = bless {}, $class;
    
    # Setup this object.
    $fs->_init(@args);
    
    # Make sure we're the only hook intercepting unmocked files.
    Test::MockFile::clear_file_access_hooks();
    Test::MockFile::add_file_access_hook( \&_unmocked_file_access_hook );
    
    return $fs;
}

sub _init {
    my $self = ($_[0] && ref $_[0] eq __PACKAGE__) ? shift @_ : $fs;
    
    my (%args) = @_;

    # Setup a default empty path.
    $fs->{'tree'}  //= Test::MockFile->dir('/', []);
}

sub _unmocked_file_access_hook {
    my ( $command, $at_under_ref ) = @_;

    my $file_arg =
        $command eq 'open'    ? 2
      : $command eq 'sysopen' ? 1
      : $command eq 'opendir' ? 1
      : $command eq 'stat'    ? 0
      : $command eq 'lstat'   ? 0
      :                         Carp::croak("Unknown strict mode violation for $command");

    my @stack;
    foreach my $stack_level ( 1 .. 100 ) {
        @stack = caller($stack_level);
        last if !scalar @stack;
        last if !defined $stack[0];                       # We don't know when this would ever happen.
        next if ( $stack[0] eq __PACKAGE__ );
        next if ( $stack[0] eq 'Test::MockFile' );
        next if ( $stack[0] eq 'Overload::FileCheck' );

        # We found a package that isn't one of ours. Is it allowed to access files?
        # If so we're not going to die.
#        return if $authorized_strict_mode_packages{ $stack[0] };

        #
        last;
    }

    if ( $command eq 'open' and scalar @$at_under_ref != 3 ) {
        $file_arg = 1 if scalar @$at_under_ref == 2;
    }

    my $filename = scalar @$at_under_ref <= $file_arg ? '<not specified>' : $at_under_ref->[$file_arg];

    # Ignore stats on STDIN, STDOUT, STDERR
    return if $filename =~ m/^\*?(?:main::)?[<*&+>]*STD(?:OUT|IN|ERR)$/;

    Carp::confess("Use of $command to access unmocked file or directory '$filename' in strict mode at $stack[1] line $stack[2]");
}

1;
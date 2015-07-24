package Params::Check;

use strict;

use Carp qw[carp];
use Locale::Maketext::Simple Style => 'gettext';

BEGIN {
    use Exporter    ();
    use vars        qw[ @ISA $VERSION @EXPORT_OK $VERBOSE $ALLOW_UNKNOWN 
                        $STRICT_TYPE $STRIP_LEADING_DASHES $NO_DUPLICATES
                        $PRESERVE_CASE
                    ];

    @ISA        =   qw[ Exporter ];
    @EXPORT_OK  =   qw[check];
    
    $VERSION                = 0.03;
    $VERBOSE                = $^W ? 1 : 0;
    $NO_DUPLICATES          = 0;
    $STRIP_LEADING_DASHES   = 0;
    $STRICT_TYPE            = 0;
    $ALLOW_UNKNOWN          = 0;
    $PRESERVE_CASE          = 0;
}


my @known_keys = qw|required allow default strict_type no_override store|;

sub check {
    my $utmpl   = shift;
    my $href    = shift;
    my $verbose = shift || $VERBOSE || 0;

    ### check for weird things in the template and warn
    ### also convert template keys to lowercase if required
    my $tmpl = _sanity_check($utmpl);

    ### lowercase all args, and handle both hashes and hashrefs ###
    my $args = {};
    if (ref($href) eq 'HASH') {
        %$args = map { _canon_key($_), $href->{$_} } keys %$href;
    
    } elsif (ref($href) eq 'ARRAY') {
    
        if (@$href == 1 && ref($href->[0]) eq 'HASH') {
            %$args = map { _canon_key($_), $href->[0]->{$_}}
                keys %{ $href->[0] };
    
        } else {
            if ( scalar @$href % 2) {
                carp loc(qq[Uneven number of arguments passed to %1], _who_was_it())
                    if $verbose;
                return undef;
            }
            
            my %realargs = @$href;
            %$args = map { _canon_key($_), $realargs{$_} } keys %realargs;
        }
    }

    ### flag to set if something went wrong ###
    my $flag;

    for my $key ( keys %$tmpl ) {

        ### check if the required keys have been entered ###
        my $rv = _hasreq( $key, $tmpl, $args );

        unless( $rv ) {
            carp loc("Required option '%1' is not provided for %2 by %3",
                        $key, _who_was_it(), _who_was_it(1),
                    ) if $verbose;
            $flag++;
        }
    }
    return undef if $flag;

    ### set defaults for all arguments ###
    my $defs = _hashdefs($tmpl);

    ### check if all keys are valid ###
    for my $key ( keys %$args ) {

        unless( _iskey( $key, $tmpl ) ) {
            if( $ALLOW_UNKNOWN ) {
                $defs->{$key} = $args->{$key} if exists $args->{$key};
            } else {
                carp loc("Key '%1' is not a valid key for %2 provided by %3",
                        $key, _who_was_it(), _who_was_it(1)
                    ) if $verbose;
                next;
            }

        } elsif ( $tmpl->{$key}->{no_override} ) {
            carp loc( qq[You are not allowed to override key '%1' for %2 from %3],
                        $key, _who_was_it(), _who_was_it(1)
                    ) if $verbose;
            next;
        } else {

            ### flag to set if the value was of a wrong type ###
            my $wrong;

            if( exists $tmpl->{$key}->{allow} ) {

                my $what = $tmpl->{$key}->{allow};

                ### it's a string it must equal ###
                ### this breaks for digits =/
                unless ( ref $what ) {
                    $wrong++ unless _safe_eq( $args->{$key}, $what );

                } elsif ( ref $what eq 'Regexp' ) {
                    $wrong++ unless $args->{$key} =~ /$what/;

                } elsif ( ref $what eq 'ARRAY' ) {
                    $wrong++ unless grep { ref $_ eq 'Regexp'
                                                ? $args->{$key} =~ /$_/
                                                : _safe_eq($args->{$key}, $_)
                                         } @$what;

                } elsif ( ref $what eq 'CODE' ) {
                    $wrong++ unless $what->( $key => $args->{$key} );

                } else {
                    carp loc(qq[Can not do allow checking based on a %1 for %2],
                                ref $what, _who_was_it()
                            );
                }
            }

            if( $STRICT_TYPE || $tmpl->{$key}->{strict_type} ) {
                $wrong++ unless ref $args->{$key} eq ref $tmpl->{$key}->{default};
            }

            ### somehow it's the wrong type.. warn for this! ###
            if( $wrong ) {
                carp loc( qq[Key '%1' is of invalid type for %2 provided by %3],
                            $key, _who_was_it(), _who_was_it(1)
                        ) if $verbose;
                ++$flag && next;

            } else {

                ### if we got here, it's apparently an ok value for $key,
                ### so we'll set it in the default to return it in a bit
                
                my $store;
                if( my $scalar = $tmpl->{$key}->{store} ) {
                    $$scalar = $args->{$key};
                    $store++;
                }
                           
                $defs->{$key} = $args->{$key} unless $store && $NO_DUPLICATES;
                
            }

        }
    }

    return $flag ? undef : $defs;
}

### Like check_array, but tmpl is an array and arguments can be given
### in a positional way; the tmpl order is the argument order.
sub check_positional {
    my $atmpl   = shift;
    my $aref    = shift;
    my $verbose = shift || $VERBOSE || 0;

    my %args;
    {
        local $STRIP_LEADING_DASHES = 1;
        my ($tmpl, $pos, $syn) = _atmpl_to_tmpl_pos_syn($atmpl);
        
        if ($#$aref == 1 && ref($aref->[0]) eq 'HASH') {
        
            ### Single hashref argument containing actual args.
            my ($key, $item);
            while (($key, $item) = each %{ $aref->[0] }) {
                $key = _canon_key($key);
                if ($syn->{$key}) {
                    # XXX Make this nonfatal ?
                    carp loc( qq[Synonym used in call to %1], _who_was_it() )
                        if $verbose;
                    $key = $syn->{$key};
                }
                $args{$key} = $item;
            }
        
        } elsif (!($#$aref % 2) && ref($aref->[0]) eq 'SCALAR' &&
                     $aref->[0] =~ /^-/) {
            
            ### List of -KEY => value pairs.
            while (my $key = (shift @$aref)) {
                $key = _canon_key($key);
                if ($syn->{$key}) {
                    # XXX Make this nonfatal ?
                    carp loc( qq[Synonym used in call to %1], _who_was_it() )
                        if $verbose;
                    $key = $syn->{$key};
                }
                $args{_convert_case($key)} = shift @$aref;
            }
        } else {
            ### Positional arguments, yay!
            while (@$aref) {
                my $item = shift @$aref;
                my $key = shift @$pos;
                if (!$key) {
                    carp loc( qq[Too many positional arguments for %1] ,
                            _who_was_it() ) if $verbose;
                    
                    ### We ran out of positional arguments, no sense in
                    ### continuing on.
                    last;
                }
                $args{$key} = $item;
            }
        }
        return check($tmpl, \%args, $verbose);
    }
}

### Return a hashref of $tmpl keys with required values
sub _listreqs {
    my $tmpl = shift;

    my %hash = map { $_ => 1 } grep { $tmpl->{$_}->{required} } keys %$tmpl;
    return \%hash;
}

### Convert template arrayref (keyword, hashref pairs) into straight ###
### hashref and an (array) mapping of position => keyname ###
sub _atmpl_to_tmpl_and_pos {
    my @atmpl = @{ shift @_ };

    my (%tmpl, @positions, %synonyms);
    while (@atmpl) {
        
        my $key = shift @atmpl;
        my $href = shift @atmpl;
        
        push @positions, $key;
        $tmpl{_convert_case($key)} = $href;
        
        for ( @{ $href->{synonyms} || [] } ) {
            $synonyms{ _convert_case($_) } = $key;
        };
        
        undef $href->{synonyms};
    };
    return (\%tmpl, \@positions, \%synonyms);
}

### Canonicalise key (lowercase, and strip leading dashes if desired) ###
sub _canon_key {
    my $key = _convert_case( +shift );
    $key =~ s/^-// if $STRIP_LEADING_DASHES;
    return $key;
}


### check if the $key is required, and if so, whether it's in $args ###
sub _hasreq {
    my ($key, $tmpl, $args ) = @_;
    my $reqs = _listreqs($tmpl);

    return $reqs->{$key}
            ? exists $args->{$key}
                ? 1
                : undef
            : 1;
}

### Return a hash of $tmpl keys with default values => defaults
### make sure to even include undefined ones, so that 'exists' will dwym
sub _hashdefs {
    my $tmpl = shift;

    my %hash =  map {
                    $_ => defined $tmpl->{$_}->{default}
                                ? $tmpl->{$_}->{default}
                                : undef
                } keys %$tmpl;

    return \%hash;
}

### check if the key exists in $data ###
sub _iskey {
    my ($key, $tmpl) = @_;
    return $tmpl->{$key} ? 1 : undef;
}

sub _who_was_it {
    my $level = shift || 0;

    return (caller(2 + $level))[3] || 'ANON'
}

sub _safe_eq {
    my($a, $b) = @_;

    if ( defined($a) && defined($b) ) {
        return $a eq $b;
    }
    else {
        return defined($a) eq defined($b);
    }
}

sub _sanity_check {
    my $tmpl = shift;
    my $rv = {};
    
    while( my($key,$href) = each %$tmpl ) {
        for my $type ( keys %$href ) {
            unless( grep { $type eq $_ } @known_keys ) {
                warn loc(q|Template type '%1' not supported [at key '%2']|, $type, $key);
            }               
        }
        $rv->{_convert_case($key)} = $href;
    }
    return $rv;
}    

sub _convert_case {
    my $key = shift;
    
    return $PRESERVE_CASE ? $key : lc $key;
}

1;

__END__

=pod

=head1 NAME

Params::Check;

=head1 SYNOPSIS

    use Params::Check qw[check];

    sub fill_personal_info {
        my %hash = @_;
        my $x;
        
        my $tmpl = {
            firstname   => { required   => 1, },
            lastname    => { required   => 1, store => \$x },
            gender      => { required   => 1,
                             allow      => [qr/M/i, qr/F/i],
                           },
            married     => { allow      => [0,1] },
            age         => { default    => 21,
                             allow      => qr/^\d+$/,
                           },
            id_list     => { default    => [],
                             strict_type => 1
                           },
            phone       => { allow => sub {
                                    my %args = @_; 
                                    return 1 
                                        if &valid($args{phone});
                                }
                            },
            employer    => { default => 'NSA', no_override => 1 },
            }
        };

        my $parsed_args = check( $tmpl, \%hash, $VERBOSE )
                            or die [Could not parse arguments!];

=head1 DESCRIPTION

Params::Check is a generic input parsing/checking mechanism.

It allows you to validate input via a template. The only requirement
is that the arguments must be named.

Params::Check can do the following things for you:

=over 4

=item *

Convert all keys to lowercase

=item *

Check if all required arguments have been provided

=item *

Set arguments that have not been provided to the default

=item *

Weed out arguments that are not supported and warn about them to the
user

=item *

Validate the arguments given by the user based on strings, regexes,
lists or even subroutines

=item *

Enforce type integrity if required

=back

Most of Params::Check's power comes from it's template, which we'll
discuss below:



=head1 Template

As you can see in the synopsis, based on your template, the arguments
provided will be validated.

The template can take a different set of rules per key that is used.

The following rules are available:

=over 4

=item default

This is the default value if none was provided by the user.
This is also the type C<strict_type> will look at when checking type
integrity (see below).

=item required

A boolean flag that indicates if this argument was a required
argument. If marked as required and not provided, check() will fail.

=item strict_type

This does a C<ref()> check on the argument provided. The C<ref> of the
argument must be the same as the C<ref> of the default value for this
check to pass.

This is very usefull if you insist on taking an array reference as
argument for example.

=item no_override

This allows you to specify C<constants> in your template. ie, they 
keys that are not allowed to be altered by the user. It pretty much
allows you to keep all your C<configurable> data in one place; the
C<Params::Check> template.

=item store

This allows you to pass a reference to a scalar, in which the data
will be stored:
    
    my $x;
    my $args = check(foo => { default => 1, store => \$x }, $input);

This is basically shorthand for saying:

    my $args = check( { foo => { default => 1 }, $input );
    my $x    = $args->{foo};   

You can alter the global variable $Params::Check::NO_DUPLICATES to
control whether the C<store>'d key will still be present in your 
result yet. See the L<Global Variables> section below.

=item allow

A set of criteria used to validate a perticular piece of data if it
has to adhere to particular rules.
You can use the following types of values for allow:

=over 4

=item string

The provided argument MUST be equal to the string for the validation
to pass.

=item array ref

The provided argument MUST equal (or match in case of a regular
expression) one of the elements of the array ref for the validation to
pass.

=item regexp

The provided argument MUST match the regular expression for the
validation to pass.

=item subroutine

The provided subroutine MUST return true in order for the validation
to pass and the argument accepted.

(This is particularly usefull for more complicated data).

=back

=back

=head1 Functions

=head2 check

Params::Check only has one function, which is called C<check>.

This function is not exported by default, so you'll have to ask for it
via:

    use Params::Check qw[check];

or use it's fully qualified name instead.

C<check> takes a list of arguments, as follows:

=over 4

=item Template

This is a hashreference which contains a template as explained in the
synopsis.

=item Arguments

This is a reference to a hash of named arguments which need checking.

=item Verbose

A boolean to indicate whether C<check> should be verbose and warn
about whant went wrong in a check or not.

=back

C<check> will return undef when it fails, or a hashref with lowercase
keys of parsed arguments when it succeeds.

So a typical call to check would look like this:

    my $parsed = check( \%template, \%arguments, $VERBOSE )
                    or warn q[Arguments could not be parsed!];


=head1 Global Variables

The behaviour of Params::Check can be altered by changing the
following global variables:

=head2 $Params::Check::VERBOSE

This controls whether CPANPLUS::Check::Module will issue warnings and
explenations as to why certain things may have failed. If you set it
to 0, Params::Check will not output any warnings.
The default is 1 when L<warnings> are enabled, 0 otherwise;

=head2 $Params::Check::STRICT_TYPE

This works like the C<strict_type> option you can pass to C<check>,
which will turn on C<strict_type> globally for all calls to C<check>.
The default is 0;

=head2 $Params::Check::ALLOW_UNKNOWN

If you set this flag, unknown options will still be present in the
return value, rather than filtered out. This is usefull if your
subroutine is only interested in a few arguments, and wants to pass
the rest on blindly to perhaps another subroutine.
The default is 0;

=head2 $Params::Check::STRIP_LEADING_DASHES

If you set this flag, all keys passed in the following manner:

    function( -key => 'val' );
    
will have their leading dashes stripped.     

=head2 $Params::Check::NO_DUPLICATES

If set to true, all keys in the template that are marked as to be
stored in a scalar, will also be removed from the result set.

Default is false, meaning that when you use C<store> as a template
key, C<check> will put it both in the scalar you supplied, as well as
in the hashref it returns.

=head2 $Params::Check::PRESERVE_CASE

If set to true, L<Params::Check> will no longer convert all keys from
the user input to lowercase, but instead expect them to be in the 
case the template provided. This is useful when you want to use 
similar keys with different casing in your templates.

Understand that this removes the case-insensitivy feature of this
module. Default is 1;

=head1 AUTHOR

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 Acknowledgements

Thanks to Ann Barcomb for her suggestions and Thomas Wouters for his
patches to support positional arguments.

=head1 COPYRIGHT

This module is
copyright (c) 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
         

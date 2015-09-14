package Getopt::Panjang;

# DATE
# VERSION

use 5.010001;
use strict 'subs', 'vars';
# IFUNBUILT
use warnings;
# END IFUNBUILT

our %SPEC;
our @EXPORT    = qw();
our @EXPORT_OK = qw(get_options);

sub import {
    my $pkg = shift;
    my $caller = caller;
    my @imp = @_ ? @_ : @EXPORT;
    for my $imp (@imp) {
        if (grep {$_ eq $imp} (@EXPORT, @EXPORT_OK)) {
            *{"$caller\::$imp"} = \&{$imp};
        } else {
            die "$imp is not exported by ".__PACKAGE__;
        }
    }
}

$SPEC{get_options} = {
    v => 1.1,
    summary => 'Parse command-line options',
    args => {
        argv => {
            summary => 'Command-line arguments, which will be parsed',
            description => <<'_',

If unspecified, will default to `@ARGV`.

_
            schema => ['array*', of=>'str*'],
        },
        spec => {
            summary => 'Options specification',
            description => <<'_',

Similar like `Getopt::Long` and `Getopt::Long::Evenless`, this argument should
be a hash. The keys should be option name specifications, while the values
should be option handlers.

Option name specification is like in `Getopt::Long::EvenLess`, e.g. `name`,
`name=s`, `name|alias=s`.

Option handler will be passed `%args` with the possible keys as follow: `name`
(str, option name), `value` (any, option value). A handler can die with an error
message to signify failed validation for the option value.

_
            schema => ['hash*', values=>'code*'],
        },
    },
    result => {
        description => <<'_',

Will return 200 on parse success. If there is an error, like missing option
value or unknown option, will return 4xx. The result metadata will contain more
information about the error.

_
    },
};

sub get_options {
    my %args = @_;

    my %unknown_opts;
    my %missing_val;
    my %invalid_val;

    my %spec_by_opt_name;
    for (keys %spec) {
        my $orig = $_;
        s/=[fios]\@?\z//;
        s/\|.+//;
        $spec_by_opt_name{$_} = $orig;
    }

    my $code_find_opt = sub {
        my ($wanted, $short_mode) = @_;
        my @candidates;
      OPT_SPEC:
        for my $spec (keys %spec) {
            $spec =~ s/=[fios]\@?\z//;
            my @opts = split /\|/, $spec;
            for my $o (@opts) {
                next if $short_mode && length($o) > 1;
                if ($o eq $wanted) {
                    # perfect match, we immediately go with this one
                    @candidates = ($opts[0]);
                    last OPT_SPEC;
                } elsif (index($o, $wanted) == 0) {
                    # prefix match, collect candidates first
                    push @candidates, $opts[0];
                    next OPT_SPEC;
                }
            }
        }
        if (!@candidates) {
            warn "Unknown option: $wanted\n";
            $success = 0;
            return undef; # means unknown
        } elsif (@candidates > 1) {
            warn "Option $wanted is ambiguous (" .
                join(", ", @candidates) . ")\n";
            $success = 0;
            return ''; # means ambiguous
        }
        return $candidates[0];
    };

    my $code_set_val = sub {
        my $name = shift;

        my $spec_key = $spec_by_opt_name{$name};
        my $handler  = $spec{$spec_key};

        $handler->({name=>$name}, @_ ? $_[0] : 1);
    };

    my $i = -1;
    my @remaining;
  ELEM:
    while (++$i < @$argv) {
        if ($argv->[$i] eq '--') {

            push @remaining, @{$argv}[$i+1 .. @$argv-1];
            last ELEM;

        } elsif ($argv->[$i] =~ /\A--(.+?)(?:=(.*))?\z/) {

            my ($used_name, $val_in_opt) = ($1, $2);
            my $opt = $code_find_opt->($used_name);
            if (!defined($opt)) {
                push @remaining, $argv->[$i];
                next ELEM;
            } elsif (!length($opt)) {
                next ELEM; # ambiguous
            }

            my $spec = $spec_by_opt_name{$opt};
            # check whether option requires an argument
            if ($spec =~ /=[fios]\@?\z/) {
                if (defined $val_in_opt) {
                    # argument is taken after =
                    if (length $val_in_opt) {
                        $code_set_val->($opt, $val_in_opt);
                    } else {
                        warn "Option $used_name requires an argument\n";
                        $success = 0;
                        next ELEM;
                    }
                } else {
                    if ($i+1 >= @$argv) {
                        # we are the last element
                        warn "Option $used_name requires an argument\n";
                        $success = 0;
                        last ELEM;
                    }
                    $i++;
                    $code_set_val->($opt, $argv->[$i]);
                }
            } else {
                $code_set_val->($opt);
            }

        } elsif ($argv->[$i] =~ /\A-(.*)/) {

            my $str = $1;
          SHORT_OPT:
            while ($str =~ s/(.)//) {
                my $used_name = $1;
                my $opt = $code_find_opt->($1, 'short');
                next SHORT_OPT unless defined($opt) && length($opt);

                my $spec = $spec_by_opt_name{$opt};
                # check whether option requires an argument
                if ($spec =~ /=[fios]\@?\z/) {
                    if (length $str) {
                        # argument is taken from $str
                        $code_set_val->($opt, $str);
                        next ELEM;
                    } else {
                        if ($i+1 >= @$argv) {
                            # we are the last element
                            warn "Option $used_name requires an argument\n";
                            $success = 0;
                            last ELEM;
                        }
                        # take the next element as argument
                        $i++;
                        $code_set_val->($opt, $argv->[$i]);
                    }
                } else {
                    $code_set_val->($opt);
                }
            }

        } else { # argument

            push @remaining, $argv->[$i];
            next;

        }
    }

  RETURN:
    splice @$argv, 0, ~~@$argv, @remaining; # replace with remaining elements
    return $success;
}

sub GetOptions {
    GetOptionsFromArray(\@ARGV, @_);
}

1;
#ABSTRACT: Parse command-line options

=for Pod::Coverage .+

=head1 DESCRIPTION

B<EXPERIMENTAL WORK>.

This module is similar to L<Getopt::Long>, but with a rather different
interface. After experimenting with L<Getopt::Long::Less> and
L<Getopt::Long::EvenLess> (which offers interface compatibility with
Getopt::Long), I'm now trying a different interface which will enable me to
"clean up" or do "more advanced" stuffs.

Here are the goals of Getopt::Panjang:

=over

=item * low startup overhead

Less than Getopt::Long, comparable to Getopt::Long::EvenLess.

=item * feature parity with Getopt::Long::EvenLess

More features will be offered in the future.

=item * more detailed error return

This is the main goal which motivates me to write Getopt::Panjang. In
Getopt::Long, if there is an error like an unknown option, or validation error
for an option's value, or missing option value, you only get a string warning.
Getopt::Panjang will instead return a data structure with more details so you
can know which option is missing the value, which unknown option is specified by
the user, etc. This will enable scripts/frameworks to do something about it,
e.g. suggest the correct option when mistyped.

=back

The interface differences with Getopt::Long:

=over

=item * There is only a single function

Getopt::Long has C<GetOptions>, C<GetOptionsFromArray>, C<GetOptionsFromString>.
We only offer C<get_options>.

=item * C<get_options> accepts hash argument

This future-proofs the function when we want to add more configuration.

=item * There are no globals

Every configuration is specified through the C<get_options> function. This is
cleaner.

=item * C<get_options> never dies, never prints warnings

It only returns the detailed error structure so you can do something about it.

=item * capitalization of function names

Lowercase with underscores (C<get_options>) is used instead of camel case
(C<GetOptions>).

=back

=back

Sample startup overhead benchmark:

# COMMAND: perl devscripts/bench-startup 2>&1


=head1 SEE ALSO

L<Getopt::Long>

L<Getopt::Long::Less>, L<Getopt::Long::EvenLess>

L<Perinci::Sub::Getopt>

=cut
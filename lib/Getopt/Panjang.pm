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
            pos => 0,
            greedy => 1,
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
            req => 1,
        },
    },
    result => {
        description => <<'_',

Will return 200 on parse success. If there is an error, like missing option
value or unknown option, will return 500. The result metadata will contain more
information about the error.

_
    },
};
sub get_options {
    my %args = @_;

    # XXX schema
    my $argv;
    if ($args{argv}) {
        ref($args{argv}) eq 'ARRAY' or return [400, "argv is not an array"];
        $argv = $args{argv};
    } else {
        $argv = \@ARGV;
    }
    my $spec = $args{spec} or return [400, "Please specify spec"];
    ref($args{spec}) eq 'HASH' or return [400, "spec is not a hash"];
    for (keys %$spec) {
        return [400, "spec->{$_} is not a coderef"]
            unless ref($spec->{$_}) eq 'CODE';
    }

    my %spec_by_opt_name;
    for (keys %$spec) {
        my $orig = $_;
        s/=[fios]\@?\z//;
        s/\|.+//;
        $spec_by_opt_name{$_} = $orig;
    }

    my $code_find_opt = sub {
        my ($wanted, $short_mode) = @_;
        my @candidates;
      OPT_SPEC:
        for my $speckey (keys %$spec) {
            $speckey =~ s/=[fios]\@?\z//;
            my @opts = split /\|/, $speckey;
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
            return [404, "Unknown option '$wanted'", undef,
                    {'func.unknown_opt' => $wanted}];
        } elsif (@candidates > 1) {
            return [300, "Option '$wanted' is ambiguous", undef, {
                'func.ambiguous_opt' => $wanted,
                'func.ambiguous_candidates' => [sort @candidates],
            }];
        }
        return [200, "OK", $candidates[0]];
    };

    my $code_set_val = sub {
        my $name = shift;

        my $speckey = $spec_by_opt_name{$name};
        my $handler = $spec->{$speckey};

        eval {
            $handler->(
                name  => $name,
                value => (@_ ? $_[0] : 1),
            );
        };
        if ($@) {
            return [400, "Invalid value for option '$name': $@", undef,
                    {'func.val_invalid_opt' => $name}];
        } else {
            return [200];
        }
    };

    my %unknown_opts;
    my %ambiguous_opts;
    my %val_missing_opts;
    my %val_invalid_opts;

    my $i = -1;
    my @remaining;
  ELEM:
    while (++$i < @$argv) {
        if ($argv->[$i] eq '--') {

            push @remaining, @{$argv}[$i+1 .. @$argv-1];
            last ELEM;

        } elsif ($argv->[$i] =~ /\A--(.+?)(?:=(.*))?\z/) {

            my ($used_name, $val_in_opt) = ($1, $2);
            my $findres = $code_find_opt->($used_name);
            if ($findres->[0] == 404) { # unknown opt
                push @remaining, $argv->[$i];
                $unknown_opts{ $findres->[3]{'func.unknown_opt'} }++;
                next ELEM;
            } elsif ($findres->[0] == 300) { # ambiguous
                $ambiguous_opts{ $findres->[3]{'func.ambiguous_opt'} } =
                    $findres->[3]{'func.ambiguous_candidates'};
                next ELEM;
            } elsif ($findres->[0] != 200) {
                return [500, "An unexpected error occurs", undef, {
                    'func._find_opt_res' => $findres,
                }];
            }
            my $opt = $findres->[2];

            my $speckey = $spec_by_opt_name{$opt};
            # check whether option requires an argument
            if ($speckey =~ /=[fios]\@?\z/) {
                if (defined $val_in_opt) {
                    # argument is taken after =
                    if (length $val_in_opt) {
                        my $setres = $code_set_val->($opt, $val_in_opt);
                        $val_invalid_opts{$opt} = $setres->[1]
                            unless $setres->[0] == 200;
                    } else {
                        $val_missing_opts{$used_name}++;
                        next ELEM;
                    }
                } else {
                    if ($i+1 >= @$argv) {
                        # we are the last element
                        $val_missing_opts{$used_name}++;
                        last ELEM;
                    }
                    $i++;
                    my $setres = $code_set_val->($opt, $argv->[$i]);
                    $val_invalid_opts{$opt} = $setres->[1]
                        unless $setres->[0] == 200;
                }
            } else {
                my $setres = $code_set_val->($opt);
                $val_invalid_opts{$opt} = $setres->[1]
                    unless $setres->[0] == 200;
            }

        } elsif ($argv->[$i] =~ /\A-(.*)/) {

            my $str = $1;
          SHORT_OPT:
            while ($str =~ s/(.)//) {
                my $used_name = $1;
                my $findres = $code_find_opt->($1, 'short');
                next SHORT_OPT unless $findres->[0] == 200;
                my $opt = $findres->[2];

                my $speckey = $spec_by_opt_name{$opt};
                # check whether option requires an argument
                if ($speckey =~ /=[fios]\@?\z/) {
                    if (length $str) {
                        # argument is taken from $str
                        my $setres = $code_set_val->($opt, $str);
                        $val_invalid_opts{$opt} = $setres->[1]
                            unless $setres->[0] == 200;
                        next ELEM;
                    } else {
                        if ($i+1 >= @$argv) {
                            # we are the last element
                            $val_missing_opts{$used_name}++;
                            last ELEM;
                        }
                        # take the next element as argument
                        $i++;
                        my $setres = $code_set_val->($opt, $argv->[$i]);
                        $val_invalid_opts{$opt} = $setres->[1]
                            unless $setres->[0] == 200;
                    }
                } else {
                    my $setres = $code_set_val->($opt);
                    $val_invalid_opts{$opt} = $setres->[1]
                        unless $setres->[0] == 200;
                }
            }

        } else { # argument

            push @remaining, $argv->[$i];
            next;

        }
    }

  RETURN:
    my ($status, $msg);
    if (!keys(%unknown_opts) && !keys(%ambiguous_opts) &&
            !keys(%val_missing_opts) && !keys(%val_invalid_opts)) {
        $status = 200;
        $msg = "OK";
    } else {
        $status = 500;
        my @errs;
        if (keys %unknown_opts) {
            push @errs, "Unknown option" .
                (keys(%unknown_opts) > 1 ? "s ":" ") .
                join(", ", map {"'$_'"} sort keys %unknown_opts);
        }
        for (sort keys %ambiguous_opts) {
            push @errs, "Ambiguous option '$_' (" .
                join("/", @{$ambiguous_opts{$_}}) . "?)";
        }
        if (keys %val_missing_opts) {
            push @errs, "Missing required value for option" .
                (keys(%val_missing_opts) > 1 ? "s ":" ") .
                join(", ", map {"'$_'"} sort keys %val_missing_opts);
        }
        for (keys %val_invalid_opts) {
            push @errs, "Invalid value for option '$_': " .
                $val_invalid_opts{$_};
        }
        $msg = (@errs > 1 ? "Errors in parsing command-line options: " : "").
            join("; ", @errs);
    }
    [$status, $msg, undef, {
        'func.remaining_argv' => \@remaining,
        ('func.unknown_opts'     => \%unknown_opts    )
            x (keys(%unknown_opts) ? 1:0),
        ('func.ambiguous_opts'   => \%ambiguous_opts  )
            x (keys(%ambiguous_opts) ? 1:0),
        ('func.val_missing_opts' => \%val_missing_opts)
            x (keys(%val_missing_opts) ? 1:0),
        ('func.val_invalid_opts' => \%val_invalid_opts)
            x (keys(%val_invalid_opts) ? 1:0),
    }];
}

1;
#ABSTRACT: Parse command-line options

=for Pod::Coverage .+

=head1 SYNOPSIS

 use Getopt::Panjang qw(get_options);

 my $opts;
 my $res = get_options(
     # similar to Getopt::Long, except values must be coderef (handler), and
     # handler receives hash argument
     spec => {
         'bar'   => sub { $opts->{bar} = 1 },
         'baz=s' => sub { my %a = @_; $opts->{baz} = $a{value} },
         'err=s' => sub { die "Bzzt\n" },
     },
     argv => ["--baz", 1, "--bar"], # defaults to @ARGV
 );

 if ($res->[0] == 200) {
     # do stuffs with parsed options, $opts
 } else {
     die $res->[1];
 }

Sample success result when C<@ARGV> is C<< ["--baz", 1, "--bar"] >>:

 [200, "OK", undef, { "func.remaining_argv" => [] }]

Sample error result (ambiguous option) when C<@ARGV> is C<< ["--ba", 1] >>:

 [
   500,
   "Ambiguous option 'ba' (bar/baz?)",
   undef,
   {
     "func.ambiguous_opts" => { ba => ["bar", "baz"] },
     "func.remaining_argv" => [1],
   },
 ]

Sample error result (option with missing value) when C<@ARGV> is C<< ["--bar",
"--baz"] >>:

[
   500,
   "Missing required value for option 'baz'",
   undef,
   {
     "func.remaining_argv"   => [],
     "func.val_missing_opts" => { baz => 1 },
   },
 ]

Sample error result (unknown option) when C<@ARGV> is C<< ["--foo", "--qux"] >>:

 [
    500,
   "Unknown options 'foo', 'qux'",
   undef,
   {
     "func.remaining_argv" => ["--foo", "--qux"],
     "func.unknown_opts"   => { foo => 1, qux => 1 },
   },
 ]

Sample error result (option with invalid value where the option handler dies)
when C<@ARGV> is C<< ["--err", 1] >>:

 [
   500,
   "Invalid value for option 'err': Invalid value for option 'err': Bzzt\n",
   undef,
   {
     "func.remaining_argv"   => [],
     "func.val_invalid_opts" => { err => "Invalid value for option 'err': Bzzt\n" },
   },
 ]


=head1 DESCRIPTION

B<EXPERIMENTAL WORK>.

This module is similar to L<Getopt::Long>, but with a rather different
interface. After experimenting with L<Getopt::Long::Less> and
L<Getopt::Long::EvenLess> (both of which offer interface compatibility with
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

=item * There is only a single function, and no default exports

Getopt::Long has C<GetOptions>, C<GetOptionsFromArray>, C<GetOptionsFromString>.
We only offer C<get_options> which must be exported explicitly.

=item * capitalization of function names

Lowercase with underscores (C<get_options>) is used instead of camel case
(C<GetOptions>).

=item * C<get_options> accepts hash argument

This future-proofs the function when we want to add more configuration.

=item * option handler also accepts hash argument

This future-proofs the handler when we want to give more arguments to the
handler.

=item * There are no globals

Every configuration is specified through the C<get_options> function. This is
cleaner.

=item * C<get_options> never dies, never prints warnings

It only returns the detailed error structure so you can do whatever with it.

=item * C<get_options> never modifies argv/C<@ARGV>

Remaining C<argv> after parsing is returned in the result metadata (as
C<func.remaining_argv>).

=back

Sample startup overhead benchmark:

# COMMAND: perl devscripts/bench-startup 2>&1


=head1 SEE ALSO

L<Getopt::Long>

L<Getopt::Long::Less>, L<Getopt::Long::EvenLess>

L<Perinci::Sub::Getopt>

=cut

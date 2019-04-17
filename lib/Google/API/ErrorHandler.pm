package Google::API::ErrorHandler;
use strict;
use warnings;
use Carp;
use Time::HiRes;

sub new {
    my ($class, $param) = @_;

    Carp::croak 'recoverable not specified' unless $param->{recoverable};
    $param->{recoverable} = $class->_make_is_recoverable($param->{recoverable});

    unless (defined $param->{ua}) {
        $param->{ua} = $class->_new_ua;
    }
    $param->{max_retries} //= 5;

    bless { %$param }, $class;
}

sub is_recoverable_error {
    my ($self, $response) = @_;
    return $self->{recoverable}->($response);
}

sub retry {
    my ($self, $request) = @_;

    my $delay = $self->_make_delay($self->{delay});

    my $response;
    for (1 .. $self->{max_retries}) {
        $response = $self->{ua}->request($request);

        if ($self->is_recoverable_error($response)) {
            Time::HiRes::sleep($delay->());
            next;
        }

        last;    # success or non-recoverable error
    }
    return $response;
}

sub _make_delay {
    my $class = shift;
    my ($delay) = @_;

    if (not defined $delay) {
        my $x = 0;
        return sub { return 2**$x++ + rand(1000) / 1000 };
    }

    return sub { return $delay } if $delay =~ /\A[0-9]+\z/;
    return $delay->() if ref $delay eq 'CODE';

    Carp::croak 'Invalid delay';
}

sub _make_is_recoverable {
    my $class = shift;
    my ($spec) = @_;
    $spec = [$spec] if ref $spec eq 'CODE';
    Carp::croak 'recoverable needs to be an ARRAY or CODE' if ref $spec ne 'ARRAY';

    my %code_recoverable;
    my @sub_recoverable;

    foreach (@$spec) {
        if (/\A[0-9]{3}\z/) {
            $code_recoverable{$_} = 1;
        }
        elsif (ref eq 'CODE') {
            push @sub_recoverable, $_;
        }
        else {
            Carp::croak "Invalid recoverable: $_";
        }
    }

    return sub {
        my ($response) = @_;
        return 1 if $code_recoverable{ $response->code };
        foreach (@sub_recoverable) {
            return 1 if $_->($response);
        }
        return;
    };
}

sub _new_ua {
    my $class = shift;
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    return $ua;
}

1;

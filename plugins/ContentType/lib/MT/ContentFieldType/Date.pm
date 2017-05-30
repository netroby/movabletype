package MT::ContentFieldType::Date;
use strict;
use warnings;

use MT::ContentFieldType::Common;
use MT::Util ();

sub html {
    MT::ContentFieldType::Common::html_datetime_common( @_, '%Y-%m-%d' );
}

sub field_html_params {
    my ( $app, $field_data ) = @_;
    my $value = $field_data->{value} || '';

    my $date = '';
    if ( defined $value && $value ne '' ) {

        # for initial_value.
        if ( $value =~ /\-/ ) {
            $value =~ tr/-//d;
            $value .= '000000';
        }

        $date = MT::Util::format_ts( "%Y-%m-%d", $value, $app->blog,
            $app->user ? $app->user->preferred_language : undef );
    }

    my $required = $field_data->{options}{required} ? 'required' : '';

    {   date     => $date,
        required => $required,
    };
}

sub data_getter {
    my ( $app, $field_data ) = @_;
    my $id   = $field_data->{id};
    my $date = $app->param( 'date-' . $id );
    $date =~ s/\D//g;
    if ( defined $date && $date ne '' ) {
        return $date . '000000';
    }
    else {
        return undef;
    }
}

1;


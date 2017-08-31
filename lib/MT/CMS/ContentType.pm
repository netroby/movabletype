# Movable Type (r) (C) 2007-2017 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

package MT::CMS::ContentType;

use strict;
use warnings;

use File::Spec;
use JSON  ();
use POSIX ();

use MT;
use MT::CMS::Common;
use MT::CategorySet;
use MT::ContentField;
use MT::ContentFieldIndex;
use MT::ContentType;
use MT::ContentData;
use MT::DateTime;
use MT::Entry;
use MT::Log;
use MT::Util ();
use MT::Serialize;

sub tmpl_param_list_common {
    my ( $cb, $app, $param, $tmpl ) = @_;
    if ($app->mode eq 'list'
        && (   $app->param('_type') eq 'content_data'
            && $app->param('type') =~ /^content_data_(\d+)$/ )
        )
    {
        my $content_type_id = $1;
        my $content_type    = MT::ContentType->load($content_type_id);
        $param->{disable_user_disp_option} = !$content_type->user_disp_option;

        my $component = MT->component('core');
        my $filename
            = File::Spec->catfile( $component->path, 'tmpl', 'cms', 'listing',
            'content_data_list_header.tmpl' );
        push @{ $param->{list_headers} },
            {
            filename  => $filename,
            component => $component->id,
            };

        $param->{saved_deleted} = $app->param('saved_deleted') ? 1 : 0;
    }
}

sub tmpl_param_edit_role {
    my ( $cb, $app, $param, $tmpl ) = @_;

    $param->{content_type_perm_groups} = MT::ContentType->permission_groups;

    # Insert content type permission template.
    my $privileges_settinggroup_node
        = $tmpl->getElementById('role-privileges');
    my $content_type_permission_node = $tmpl->createElement( 'loop',
        { name => 'content_type_perm_groups' } );
    $content_type_permission_node->innerHTML(
        _content_type_permission_tmpl() );
    $privileges_settinggroup_node->appendChild($content_type_permission_node);
}

sub _content_type_permission_tmpl {
    return <<'__TMPL__';
    <mt:setvarblock name="ct_perm_group"><mt:var name="__VALUE__"></mt:setvarblock>
    <mtapp:setting
      id="<mt:var name="ct_perm_group">"
      label="<mt:var name="ct_perm_group">"
    >
      <ul class="fixed-width multiple-selection">
      <mt:loop name="loaded_permissions">
      <mt:if name="group" eq="$ct_perm_group">
        <li><label for="<mt:var name="id">"><input id="<mt:var name="id">" type="checkbox" onclick="togglePerms(this, '<mt:var name="children">')" class="<mt:var name="id"> cb" name="permission" value="<mt:var name="id">"<mt:if name="can_do"> checked="checked"</mt:if>> <mt:var name="label" escape="html"></label></li>
      </mt:if>
      </mt:loop>
      </ul>
    </mtapp:setting>
__TMPL__
}

sub cfg_content_type_description {
    my ( $app, $param ) = @_;
    $app->build_page( $app->load_tmpl('cfg_content_type_description.tmpl'),
        $param );
}

sub cfg_content_type {
    my ( $app, $param ) = @_;
    my $q   = $app->param;
    my $cfg = $app->config;

    require MT::Promise;
    my $content_type_id = $q->param('id');
    my $obj_promise     = MT::Promise::delay(
        sub {
            return undef unless $content_type_id;
            return MT::ContentType->load( { id => $content_type_id } );
        }
    );

    my $content_type = $obj_promise->force();
    if ($content_type) {
        $param->{name}             = $content_type->name;
        $param->{description}      = $content_type->description;
        $param->{unique_id}        = $content_type->unique_id;
        $param->{user_disp_option} = $content_type->user_disp_option;
        my $field_data;
        if ( $q->param('err_msg') ) {
            $field_data = $q->param('fields');
            if ( $field_data =~ /^".*"$/ ) {
                $field_data =~ s/^"//;
                $field_data =~ s/"$//;
                $field_data = MT::Util::decode_js($field_data);
            }
            $field_data
                = JSON::decode_json( MT::Util::decode_url($field_data) );
        }
        else {
            $field_data = $content_type->fields;
        }
        my @array = map {
            $_->{content_field_id} = $_->{id};
            delete $_->{id};
            my $type    = $_->{type};
            my @options = ();
            foreach my $key ( keys %{ $_->{options} } ) {
                if ( $type eq 'date_and_time' && $key eq 'initial_value' ) {
                    my ( $date, $time ) = split ' ', $_->{options}{$key};
                    push @options,
                        {
                        key   => 'initial_date',
                        value => $date
                        },
                        {
                        key   => 'initial_time',
                        value => $time
                        };
                }
                elsif (
                    (      $type eq 'select_box'
                        || $type eq 'radio_button'
                        || $type eq 'checkboxes'
                    )
                    && $key eq 'values'
                    )
                {
                    my $count  = 1;
                    my $values = delete $_->{options}{$key};
                    foreach my $trio ( @{$values} ) {
                        push @options,
                            {
                            key   => 'values_initial_' . $count,
                            value => $trio->{initial},
                            },
                            {
                            key   => 'values_label_' . $count,
                            value => $trio->{label},
                            },
                            {
                            key   => 'values_value_' . $count,
                            value => $trio->{value},
                            };
                        $count++;
                    }
                }
                else {
                    push @options,
                        {
                        key   => $key,
                        value => $_->{options}{$key}
                        };
                }
            }
            $_->{options} = \@options;
            $_;
        } @{$field_data};
        @array = sort { $a->{order} <=> $b->{order} } @array;
        $param->{fields} = \@array;
    }

    # Content Field Types
    my $content_field_types = $app->registry('content_field_types');
    my @type_array          = map {
        my $hash = {};
        $hash->{type}    = $_;
        $hash->{label}   = $content_field_types->{$_}{label};
        $hash->{options} = $content_field_types->{$_}{options};
        $hash->{order}   = $content_field_types->{$_}{order};
        $hash;
    } keys %$content_field_types;
    @type_array = sort { $a->{order} <=> $b->{order} } @type_array;
    $param->{content_field_types} = \@type_array;

    # Content Filed Type Options
    my %content_field_types_option_settings = ();
    my %content_field_types_options         = map {
        my $type_name = $_->{type};
        (   $_->{type} => [
                map {
                    if ( ref($_) eq 'HASH' ) {
                        my $key = ( keys( %{$_} ) )[0];
                        $content_field_types_option_settings{$type_name}{$key}
                            = $_->{$key};
                        $key;
                    }
                    else {
                        $_;
                    }
                } @{ $_->{options} }
            ]
            )
        }
        grep { $_->{options} } @type_array;
    $param->{content_field_types_options}
        = JSON::encode_json( \%content_field_types_options );

    foreach my $name (qw( saved err_msg id name )) {
        $param->{$name} = $q->param($name) if $q->param($name);
    }

    my @category_sets;
    my $cs_iter = MT::CategorySet->load_iter( { blog_id => $app->blog->id },
        { fetchonly => { id => 1, name => 1 } } );
    while ( my $cat_set = $cs_iter->() ) {
        push @category_sets,
            {
            id   => $cat_set->id,
            name => $cat_set->name,
            };
    }
    $param->{category_sets} = \@category_sets;

    my $content_type_loop
        = MT::ContentType->get_related_content_type_loop( $app->blog->id,
        $content_type_id );
    $param->{content_types} = $content_type_loop;

    my $tag_delim = $app->config('DefaultUserTagDelimiter') || ord(',');
    $param->{tag_delim}
        = $tag_delim eq ord(',') ? 'comma'
        : $tag_delim eq ord(' ') ? 'space'
        :                          'comma';

    # Content Field Options
    foreach my $key ( keys %$content_field_types ) {

        if ( my $options_html = $content_field_types->{$key}{options_html} ) {
            if ( !ref $options_html ) {
                if ( $options_html =~ /\.tmpl$/ ) {
                    my $plugin = $content_field_types->{$key}{plugin};
                    $options_html
                        = $plugin->id eq 'core'
                        ? $app->load_tmpl($options_html)
                        : $plugin->load_tmpl($options_html);
                    $options_html = $options_html->text if $options_html;
                }
                else {
                    $options_html = MT->handler_to_coderef($options_html);
                }
            }
            if ( 'CODE' eq ref $options_html ) {
                push @{ $param->{options_htmls} },
                    { id => $key, html => $options_html->( $app, $key ) };
            }
            else {
                push @{ $param->{options_htmls} },
                    { id => $key, html => $options_html };
            }
        }
    }

    $app->build_page( $app->load_tmpl('cfg_content_type.tmpl'), $param );
}

sub save_cfg_content_type {
    my ($app) = @_;
    my $q     = $app->param;
    my $cfg   = $app->config;
    my $param = {};

    $app->validate_magic
        or return $app->errtrans("Invalid request.");
    my $perms = $app->permissions;
    return $app->permission_denied()
        unless $app->user->is_superuser()
        || ( $perms
        && $perms->can_administer_blog );

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");

    my $content_type_id = $q->param('id');

    my $option_list;
    if ( my $data = $q->param('data') ) {
        if ( $data =~ /^".*"$/ ) {
            $data =~ s/^"//;
            $data =~ s/"$//;
            $data = MT::Util::decode_js($data);
        }
        my $decode = JSON->new->utf8(0);
        $option_list = $decode->decode($data);
    }
    else {
        $option_list = {};
    }

    my $name        = $option_list->{name};
    my $description = $option_list->{description};

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_content_type',
            args   => {
                blog_id => $blog_id,
                id      => $content_type_id,
                err_msg => $app->translate("Name is required."),
            }
        )
    ) unless $name;

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_content_type',
            args   => {
                blog_id => $blog_id,
                id      => $content_type_id,
                err_msg => $app->translate(
                    "Name \"[_1]\" is already used.", $name
                ),
            }
        )
    ) if !$content_type_id && MT::ContentType->count( { name => $name } );

    my $content_type
        = $content_type_id
        ? MT::ContentType->load($content_type_id)
        : MT::ContentType->new();

    $content_type->blog_id($blog_id);
    $content_type->name($name);
    $content_type->user_disp_option( $app->param('user_disp_option') );

    $content_type->save
        or return $app->error(
        $app->translate(
            "Saving content type failed: [_1]",
            $content_type->errstr
        )
        );

    my @field_data    = ();
    my @field_objects = ();
    my $err_msg       = '';
    foreach my $field_id ( keys %{ $option_list->{fields} } ) {
        my $type    = $option_list->{fields}{$field_id}{type};
        my $options = $option_list->{fields}{$field_id}{options};
        my $label   = $options->{label};

        $err_msg
            = _validate_content_field_type_options( $app, $content_type,
            $option_list->{fields}{$field_id}, $err_msg );

        if ( $type eq 'date_and_time' ) {
            my $date = delete $options->{initial_date};
            my $time = delete $options->{initial_time};
            $options->{initial_value} = "$date $time";
        }
        elsif ($type eq 'select_box'
            || $type eq 'radio_button'
            || $type eq 'checkboxes' )
        {
            my $count  = 1;
            my @values = ();
            while ( $options->{ 'values_label_' . $count } ) {
                my $label = delete $options->{ 'values_label_' . $count };
                my $value = delete $options->{ 'values_value_' . $count };
                push @values,
                    {
                    label => $label,
                    value => $value
                    };
                $count++;
            }
            $options->{values} = \@values;
        }
        my $content_field;
        if ( $content_type_id && !$option_list->{fields}{$field_id}{new} ) {
            $content_field = MT::ContentField->load($field_id);
        }
        unless ($content_field) {
            $content_field = MT::ContentField->new;
            $content_field->blog_id($blog_id);
            $content_field->content_type_id( $content_type->id );
            $content_field->type($type);
        }
        $content_field->name($label);
        $content_field->default( $options->{initial_value} );
        $content_field->description( $options->{description} );
        $content_field->required( $options->{required} );

        if ( $content_field->type eq 'categories' ) {
            $content_field->related_cat_set_id( $options->{category_set} );
        }
        else {
            $content_field->related_cat_set_id(undef);
        }

        if ( $content_field->type eq 'content_type' ) {
            $content_field->related_content_type_id(
                $options->{content_type} );
        }
        else {
            $content_field->related_content_type_id(undef);
        }

        # Push content field object
        push @field_objects, $content_field;

        delete $option_list->{fields}{$field_id}{new}
            if defined $option_list->{fields}{$field_id}{new};
        $option_list->{fields}{$field_id}{options} = $options;
        push @field_data,
            {
            id => $content_field->id || $field_id,
            unique_id => $content_field->unique_id,
            %{ $option_list->{fields}{$field_id} }
            };
    }

    # Validation error
    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_content_type',
            args   => {
                blog_id => $blog_id,
                id      => $content_type_id,
                fields =>
                    MT::Util::encode_url( JSON::encode_json( \@field_data ) ),
                err_msg => $app->translate($err_msg),
            }
        )
    ) if $err_msg;

    # Save content fields
    foreach my $content_field (@field_objects) {
        $content_field->save
            or return $app->error(
            $app->translate(
                "Saving content field failed: [_1]",
                $content_type->errstr
            )
            );
    }

    # Remove fields
    foreach my $field_id (
        split( ',', ( $option_list->{removed_fields} || '' ) ) )
    {
        if ( my $content_field = MT::ContentField->load($field_id) ) {
            $content_field->remove
                or return $app->error(
                $app->translate(
                    "Removing content type failed: [_1]",
                    $content_type->errstr
                )
                );
        }
    }

    # Set id and unique_id to fields if not.
    for ( my $i = 0; $i < @field_data; $i++ ) {
        my $field = $field_data[$i];
        next if $field->{id} && $field->{unique_id};
        my $content_field = $field_objects[$i];
        $field->{id}        = $content_field->id;
        $field->{unique_id} = $content_field->unique_id;
    }

    $content_type->fields( \@field_data );

    $content_type->save
        or return $app->error(
        $app->translate(
            "Saving content type failed: [_1]",
            $content_type->errstr
        )
        );

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_content_type',
            args   => {
                blog_id => $blog_id,
                id      => $content_type->id,
                saved   => 1,
            }
        )
    );
}

sub _validate_content_field_type_options {
    my ( $app, $content_type, $field_data, $err_msg ) = @_;

    my $type    = $field_data->{type};
    my $options = $field_data->{options};
    my $label   = $options->{label};

    unless ($err_msg) {
        my $content_field_types = $app->registry('content_field_types');
        my $field_label         = $content_field_types->{$type}{label};

        if ( !$options->{label} ) {
            $err_msg = $app->translate( '[_1]\'s "[_2]" field is required.',
                $field_label, 'Label' );
        }
        elsif ( length( $options->{label} ) > 255 ) {
            $err_msg = $app->translate(
                '[_1]\'s "[_2]" field should be shorter than [_3] characters.',
                $field_label, 'Label', '255'
            );
        }
        elsif ( length( $options->{description} ) > 1024 ) {
            $err_msg = $app->translate(
                '[_1]\'s "[_2]" field should be shorter than [_3] characters.',
                $field_label, 'Description', '1024'
            );
        }
        return $err_msg if $err_msg;

        if ( my $ss_validator
            = $content_field_types->{$type}{options_ss_validator} )
        {
            if ( !ref $ss_validator ) {
                $ss_validator = MT->handler_to_coderef($ss_validator);
            }
            if ( 'CODE' eq ref $ss_validator ) {
                $err_msg = $ss_validator->( $app, $type, $options );
            }
        }
        return $err_msg if $err_msg;

        if ( $type eq 'single_line_text' ) {
            my $min_length    = $options->{min_length};
            my $max_length    = $options->{max_length};
            my $initial_value = $options->{initial_value};
            if ($min_length) {
                if ( $min_length !~ /^[+\-]?\d+$/
                    || ( $min_length < 0 || $min_length > 1024 ) )
                {
                    $err_msg = $app->translate(
                        '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                        $label || $field_label,
                        'Min Length',
                        '0',
                        '1024'
                    );
                }
            }
            if ( !$err_msg && $max_length ) {
                if ( $max_length !~ /^[+\-]?\d+$/
                    || ( $max_length < 1 || $max_length > 1024 ) )
                {
                    $err_msg = $app->translate(
                        '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                        $label || $field_label,
                        'Max Length',
                        '1',
                        '1024'
                    );
                }
            }
            if ( !$err_msg && $initial_value ) {
                if ( length($initial_value) > 1024 ) {
                    $err_msg = $app->translate(
                        '[_1]\'s "[_2]" field should be shorter than [_3] characters.',
                        $field_label, 'Initial Value', '1024'
                    );
                }
            }
        }
        elsif ( $type eq 'number' ) {
            if ( !$options->{decimal_places} ) {
                my $min_value     = $options->{min_value};
                my $max_value     = $options->{max_value};
                my $initial_value = $options->{initial_value};
                if ($min_value) {
                    if (   $min_value !~ /^[+\-]?\d+$/
                        || $min_value < -2147483648
                        || $min_value > 2147483647 )
                    {
                        $err_msg = $app->translate(
                            '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                            $label || $field_label,
                            'Min Value',
                            '-2147483648',
                            '2147483647'
                        );
                    }
                }
                elsif ( !$err_msg && $max_value ) {
                    if (   $max_value !~ /^[+\-]?\d+$/
                        || $max_value < -2147483648
                        || $max_value > 2147483647
                        || ( $min_value && $min_value > $max_value ) )
                    {
                        $err_msg = $app->translate(
                            '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                            $label || $field_label,
                            'Max Value',
                            $min_value || '-2147483648',
                            '2147483647'
                        );
                    }
                }
                elsif ( !$err_msg && $initial_value ) {
                    if (   $initial_value !~ /^[+\-]?\d+$/
                        || $initial_value < -2147483648
                        || $initial_value > 2147483647 )
                    {
                        $err_msg = $app->translate(
                            '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                            $label || $field_label,
                            'Initial Value',
                            '-2147483648',
                            $min_value || '2147483647'
                        );
                    }
                }
            }
            else {
                my ( $option_label, $type )
                    = (    $options->{min_value}
                        && $options->{min_value} !~ /^[+\-]?\d+(\.\d+)?$/ )
                    ? ( $app->translate('Min Value'), 'float' )
                    : (    $options->{max_value}
                        && $options->{max_value} !~ /^[+\-]?\d+(\.\d+)?$/ )
                    ? ( $app->translate('Max Value'), 'float' )
                    : (    $options->{initial_value}
                        && $options->{initial_value}
                        !~ /^[+\-]?\d+(\.\d+)?$/ )
                    ? ( $app->translate('Initial Value'), 'float' )
                    : (    $options->{decimal_places}
                        && $options->{decimal_places} !~ /^[+\-]?\d+$/ )
                    ? ( $app->translate('Number of decimal places'),
                    'integer' )
                    : '';
                if ($option_label) {
                    $err_msg = $app->translate(
                        '[_1]\'s "[_2]" field value must be [_3].',
                        $label || $field_label,
                        $option_label, $type
                    );
                }
            }
        }
        elsif ( $type eq 'url' ) {
            my $initial_value = $options->{initial_value};
            if ( length($initial_value) > 2000 ) {
                $err_msg = $app->translate(
                    '[_1]\'s "[_2]" field should be shorter than [_3] characters.',
                    $label || $field_label,
                    'Initial Value',
                    '2000'
                );
            }
            elsif (defined $initial_value
                && $initial_value ne ''
                && !MT::Util::is_url($initial_value) )
            {
                $err_msg = MT->translate(
                    '[_1]\'s "[_2]" field is invalid.',
                    $label || $field_label,
                    'Initial Value'
                );
            }
        }
        elsif ($type eq 'date_and_time'
            || $type eq 'date'
            || $type eq 'time' )
        {
            my $date = $options->{initial_date} || '19700101';
            my $time = $options->{initial_time} || '000000';
            my $ts   = "$date $time";
            if ( !MT::Util::is_valid_date($ts) ) {
                $err_msg = $app->translate( "Invalid [_1]: '[_2]'",
                    $label || $field_label, $ts );
            }
        }
        elsif ($type eq 'select_box'
            || $type eq 'checkboxes'
            || $type eq 'radio_button' )
        {
            my $values_count = 0;
            while ( $options->{ 'values_label_' . ( $values_count + 1 ) } ) {
                $values_count++;
            }
            if ( $values_count == 0 ) {
                $err_msg
                    = $app->translate( "[_1]'s \"Values\" field is required.",
                    $label || $field_label );
            }
            if ( !$err_msg && $type ne 'radio_button' ) {
                my $min = $options->{min};
                my $max = $options->{max};
                if ( $options->{multiple} ) {
                    if ( !$min && $min eq '' ) {
                        $err_msg = $app->translate(
                            "[_1]'s \"Min\" field is required when \"Multiple\" is checked.",
                            $label || $field_label
                        );
                    }
                    elsif ( !$max ) {
                        $err_msg = $app->translate(
                            "[_1]'s \"Max\" field is required when \"Multiple\" is checked.",
                            $label || $field_label
                        );
                    }
                    elsif ( $max > $values_count ) {
                        $err_msg = $app->translate(
                            "[_1]'s \"Max\" field should be lower than number of \"Values\" field.",
                            $label || $field_label
                        );
                    }
                    elsif ( $min !~ /^[+]?\d+$/ ) {
                        $err_msg = $app->translate(
                            '[_1]\'s "[_2]" field must be a positive integer.',
                            $label || $field_label,
                            'Min'
                        );
                    }
                    elsif ( $max !~ /^[+]?\d+$/ ) {
                        $err_msg = $app->translate(
                            '[_1]\'s "[_2]" field must be a positive integer.',
                            $label || $field_label,
                            'Max'
                        );
                    }
                    elsif ( $max && $max < $min ) {
                        $err_msg = $app->translate(
                            '[_1]\'s "[_2]" field must be [_3] than "[_4]" field.',
                            $label || $field_label, 'Min', 'lower', 'Max'
                        );
                    }
                    elsif ( $min && $min > $max ) {
                        $err_msg = $app->translate(
                            '[_1]\'s "[_2]" field must be [_3] than "[_4]" field.',
                            $label || $field_label, 'Max', 'higher', 'Min'
                        );
                    }
                }
            }
        }
        elsif ($type eq 'content_type'
            || $type eq 'asset'
            || $type eq 'audio'
            || $type eq 'video'
            || $type eq 'image'
            || $type eq 'categories'
            || $type eq 'tags' )
        {
            if ( $options->{multiple} ) {
                my $min = $options->{min};
                my $max = $options->{max};
                if ( !$min ) {
                    $err_msg = $app->translate(
                        "[_1]'s \"Min\" field is required when \"Multiple\" is checked.",
                        $label || $field_label
                    );
                }
                elsif ( !$max ) {
                    $err_msg = $app->translate(
                        "[_1]'s \"Max\" field is required when \"Multiple\" is checked.",
                        $label || $field_label
                    );
                }
                elsif ($min !~ /^[+\-]?\d+$/
                    || ( $min < 0 || $min > 255 )
                    || ( $max && $max < $min ) )
                {
                    $err_msg = $app->translate(
                        '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                        $label || $field_label, 'Min', '0', '255'
                    );
                }
                elsif ($max !~ /^[+\-]?\d+$/
                    || ( $max < 1 || $max > 255 )
                    || ( $min && $min > $max ) )
                {
                    $err_msg = $app->translate(
                        '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                        $label || $field_label, 'Max', '1', '255'
                    );
                }
            }

            if ( $type eq 'content_type' && $content_type->id ) {
                if ($content_type->is_parent_content_type_id(
                        $options->{content_type}
                    )
                    )
                {
                    $err_msg = $app->translate(
                        q{[_1]'s "[_2]" field must not be parent content type.},
                        $label || $field_label,
                        'Content Type'
                    );
                }
            }
        }
        elsif ( $err_msg && $type eq 'tags' && $options->{initial_value} ) {
            my $initial_value = $options->{initial_value};
            if ( length($initial_value) > 255 ) {
                $err_msg = $app->translate(
                    '[_1]\'s "[_2]" field should be shorter than [_3] characters.',
                    $label || $field_label,
                    'Initial Value',
                    '255'
                );
            }
        }
        elsif ( $type eq 'table' ) {
            my ($initial_rows, $initial_columns,
                $row_heading,  $column_heading
                )
                = map { $options->{$_} }
                qw/ initial_rows initial_columns row_heading column_heading /;
            if ($initial_rows
                && ( $initial_rows !~ /^[+\-]?\d+$/
                    || ( $initial_rows < 0 || $initial_rows > 255 ) )
                )
            {
                $err_msg = $app->translate(
                    '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                    $label || $field_label,
                    'Initial Rows',
                    '0',
                    '255'
                );
            }
            elsif (
                $initial_columns
                && ( $initial_columns !~ /^[+\-]?\d+$/
                    || ( $initial_columns < 0 || $initial_columns > 255 ) )
                )
            {
                $err_msg = $app->translate(
                    '[_1]\'s "[_2]" field must be an integer value between [_3] and [_4].',
                    $label || $field_label,
                    'Initial Columns',
                    '0',
                    '255'
                );
            }
            elsif ( $row_heading && length($row_heading) > 255 ) {
                $err_msg = $app->translate(
                    '[_1]\'s "[_2]" field should be shorter than [_3] characters.',
                    $label || $field_label,
                    'Row Headers',
                    '255'
                );
            }
            elsif ( $column_heading && length($column_heading) > 255 ) {
                $err_msg = $app->translate(
                    '[_1]\'s "[_2]" field should be shorter than [_3] characters.',
                    $label || $field_label,
                    'Column Headers',
                    '255'
                );
            }
        }
    }

    return $err_msg;
}

sub select_list_content_type {
    my ($app) = @_;
    my $q     = $app->param;
    my $cfg   = $app->config;
    my $param = {};

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");

    my @content_types;
    my $iter = MT::ContentType->load_iter( { blog_id => $blog_id } );
    while ( my $ct = $iter->() ) {
        push @content_types, $ct;
    }
    $param->{content_types} = \@content_types;

    $app->build_page( $app->load_tmpl('content_data/select_list.tmpl'),
        $param );
}

sub select_edit_content_type {
    my ($app) = @_;
    my $q     = $app->param;
    my $cfg   = $app->config;
    my $param = {};

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");

    my @array;
    my $iter = MT::ContentType->load_iter( { blog_id => $blog_id } );
    while ( my $content_type = $iter->() ) {
        my $hash = {};
        $hash->{id}      = $content_type->id;
        $hash->{blog_id} = $content_type->blog_id;
        $hash->{name}    = $content_type->name;
        my $unique_id = $content_type->unique_id;
        $hash->{can_edit} = 1
            if $app->permissions->can_do(
            'manage_content_type:' . $unique_id );
        push @array, $hash;
    }
    $param->{content_types} = \@array;

    $app->build_page( $app->load_tmpl('content_data/select_edit.tmpl'),
        $param );
}

sub save_content_data {
    my ($app) = @_;
    my $blog  = $app->blog;
    my $q     = $app->param;
    my $cfg   = $app->config;
    my $param = {};

    $app->validate_magic
        or return $app->errtrans("Invalid request.");
    my $perms = $app->permissions;
    return $app->permission_denied()
        unless $app->user->is_superuser()
        || ( $perms
        && $perms->can_administer_blog );

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");
    my $content_type_id = scalar $q->param('content_type_id')
        or return $app->errtrans("Invalid request.");

    my $content_type = MT::ContentType->load($content_type_id);
    my $field_data   = $content_type->fields;

    my $content_data_id = scalar $q->param('id');

    my $content_field_types = $app->registry('content_field_types');

    my $convert_breaks = {};
    my $data           = {};
    foreach my $f (@$field_data) {
        my $content_field_type = $content_field_types->{ $f->{type} };
        $data->{ $f->{id} }
            = _get_form_data( $app, $content_field_type, $f );
        if ( $f->{type} eq 'multi_line_text' ) {
            $convert_breaks->{ $f->{id} } = $q->param(
                'content-field-' . $f->{id} . '_convert_breaks' );
        }
    }

    if ( $app->param('_autosave') ) {
        return _autosave_content_data( $app, $data );
    }

    if ( my $errors = _validate_content_fields( $app, $content_type, $data ) )
    {

        # FIXME: this does not preserve content field values.
        return $app->redirect(
            $app->uri(
                mode => 'edit_content_data',
                args => {
                    blog_id         => $blog_id,
                    content_type_id => $content_type_id,
                    id              => $content_data_id,
                    err_msg         => $errors->[0]{error},
                },
            )
        );
    }

    my $content_data
        = $content_data_id
        ? MT::ContentData->load($content_data_id)
        : MT::ContentData->new();

    my $orig = $content_data->clone;
    my $status_old = $content_data_id ? $content_data->status : 0;

    if ( $content_data->id ) {
        $content_data->modified_by( $app->user->id );
    }
    else {
        $content_data->author_id( $app->user->id );
        $content_data->blog_id($blog_id);
    }
    $content_data->content_type_id($content_type_id);
    $content_data->data($data);

    $content_data->title( scalar $app->param('title') );

    if ( $app->param('scheduled') ) {
        $content_data->status( MT::Entry::FUTURE() );
    }
    else {
        $content_data->status( scalar $q->param('status') );
    }
    if ( ( $content_data->status || 0 ) != MT::Entry::HOLD() ) {
        if ( !$blog->site_path || !$blog->site_url ) {
            return $app->error(
                $app->translate(
                    "Your blog has not been configured with a site path and URL. You cannot publish entries until these are defined."
                )
            );
        }
    }

    my $ao_d = $q->param('authored_on_date');
    my $ao_t = $q->param('authored_on_time');
    my $uo_d = $q->param('unpublished_on_date');
    my $uo_t = $q->param('unpublished_on_time');

    # TODO: permission check
    if ($ao_d) {
        my %param = ();
        my $ao    = $ao_d . ' ' . $ao_t;
        unless ( $ao
            =~ m!^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$!
            )
        {
            $param{error} = $app->translate(
                "Invalid date '[_1]'; 'Published on' dates must be in the format YYYY-MM-DD HH:MM:SS.",
                $ao
            );
        }
        unless ( $param{error} ) {
            my $s = $6 || 0;
            $param{error} = $app->translate(
                "Invalid date '[_1]'; 'Published on' dates should be real dates.",
                $ao
                )
                if (
                   $s > 59
                || $s < 0
                || $5 > 59
                || $5 < 0
                || $4 > 23
                || $4 < 0
                || $2 > 12
                || $2 < 1
                || $3 < 1
                || ( MT::Util::days_in( $2, $1 ) < $3
                    && !MT::Util::leap_day( $1, $2, $3 ) )
                );
        }
        $param{return_args} = $app->param('return_args');
        return $app->forward( "view", \%param ) if $param{error};
        my $ts = sprintf "%04d%02d%02d%02d%02d%02d", $1, $2, $3, $4, $5,
            ( $6 || 0 );
        $content_data->authored_on($ts);
    }

    # TODO: permission check
    if ( $content_data->status != MT::Entry::UNPUBLISH() ) {
        if ( $uo_d || $uo_t ) {
            my %param = ();
            my $uo    = $uo_d . ' ' . $uo_t;
            $param{error} = $app->translate(
                "Invalid date '[_1]'; 'Unpublished on' dates must be in the format YYYY-MM-DD HH:MM:SS.",
                $uo
                )
                unless ( $uo
                =~ m!^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$!
                );
            unless ( $param{error} ) {
                my $s = $6 || 0;
                $param{error} = $app->translate(
                    "Invalid date '[_1]'; 'Unpublished on' dates should be real dates.",
                    $uo
                    )
                    if (
                       $s > 59
                    || $s < 0
                    || $5 > 59
                    || $5 < 0
                    || $4 > 23
                    || $4 < 0
                    || $2 > 12
                    || $2 < 1
                    || $3 < 1
                    || ( MT::Util::days_in( $2, $1 ) < $3
                        && !MT::Util::leap_day( $1, $2, $3 ) )
                    );
            }
            my $ts = sprintf "%04d%02d%02d%02d%02d%02d", $1, $2, $3, $4, $5,
                ( $6 || 0 );
            unless ( $param{error} ) {
                $param{error} = $app->translate(
                    "Invalid date '[_1]'; 'Unpublished on' dates should be dates in the future.",
                    $uo
                    )
                    if (
                    MT::DateTime->compare(
                        blog => $blog,
                        a    => { value => time(), type => 'epoch' },
                        b    => $ts
                    ) > 0
                    );
            }
            if ( !$param{error} && $content_data->authored_on ) {
                $param{error} = $app->translate(
                    "Invalid date '[_1]'; 'Unpublished on' dates should be later than the corresponding 'Published on' date.",
                    $uo
                    )
                    if (
                    MT::DateTime->compare(
                        blog => $blog,
                        a    => $content_data->authored_on,
                        b    => $ts
                    ) > 0
                    );
            }
            $param{show_input_unpublished_on} = 1 if $param{error};
            $param{return_args} = $app->param('return_args');
            return $app->forward( "view", \%param ) if $param{error};
            $content_data->unpublished_on($ts);
        }
        else {
            $content_data->unpublished_on(undef);
        }
    }
    $content_data->convert_breaks(
        MT::Serialize->serialize( \$convert_breaks ) );

    $content_data->block_editor_data( $app->param('blockeditor-data') );

    $app->run_callbacks( 'cms_pre_save.cd', $app, $content_data, $orig );

    $content_data->save
        or return $app->error(
        $app->translate(
            "Saving [_1] failed: [_2]", $content_type->name,
            $content_data->errstr
        )
        );

    $app->run_callbacks( 'cms_post_save.cd', $app, $content_data, $orig );

    return $app->redirect(
        $app->uri(
            'mode' => 'edit_content_data',
            args   => {
                blog_id         => $blog_id,
                content_type_id => $content_type_id,
                id              => $content_data->id,
                saved           => 1,
            }
        )
    );
}

sub _autosave_content_data {
    my ( $app, $data ) = @_;

    my $sess_obj = $app->autosave_session_obj(1) or return;
    $sess_obj->data('');
    my %data = $app->param_hash;
    delete $data{_autosave};
    delete $data{magic_token};
    $data{data} = $data;

    foreach my $c ( keys %data ) {
        $sess_obj->set( $c, $data{$c} );
    }
    $sess_obj->start(time);
    $sess_obj->save;
    $app->send_http_header("text/javascript+json");
    $app->{no_print_body} = 1;
    $app->print_encode("true");

}

sub _get_form_data {
    my ( $app, $content_field_type, $form_data ) = @_;

    if ( my $data_load_handler = $content_field_type->{data_load_handler} ) {
        if ( !ref $data_load_handler ) {
            $data_load_handler = MT->handler_to_coderef($data_load_handler);
        }
        if ( 'CODE' eq ref $data_load_handler ) {
            return $data_load_handler->( $app, $form_data );
        }
        else {
            return $data_load_handler;
        }
    }
    else {
        my $value = $app->param( 'content-field-' . $form_data->{id} );
        if ( defined $value && $value ne '' ) {
            $value;
        }
        else {
            undef;
        }
    }
}

sub delete_content_data {
    my $app = shift;

    my $orig_type = $app->param('_type');
    my ($content_type_id) = $orig_type =~ /^content_data_(\d+)$/;

    $app->param( '_type', 'cd' );
    unless ( $app->param('content_type_id') ) {
        $app->param( 'content_type_id', $content_type_id );
    }

    MT::CMS::Common::delete($app);
}

sub dialog_content_data_modal {
    my $app = shift;

    my ( $can_add, $can_multi, $content_type_id, $content_type_name );
    my $content_field_id = $app->param('content_field_id');
    if ($content_field_id) {
        if ( my $content_field = MT::ContentField->load($content_field_id) ) {
            my $options = $content_field->options;
            $can_multi = $options->{multiple} ? 1 : 0;
            $content_type_id = $content_field->related_content_type_id;
            if ( my $content_type = $content_field->related_content_type ) {
                $content_type_name = $content_type->name;
            }
        }
    }

    my $param = {
        can_multi         => $can_multi,
        content_field_id  => $content_field_id,
        content_type_id   => $content_type_id,
        content_type_name => $content_type_name,
    };

    $app->load_tmpl( 'dialog/content_data_modal.tmpl', $param );
}

sub dialog_list_content_data {
    my $app              = shift;
    my $blog             = $app->blog;
    my $content_field_id = $app->param('content_field_id') || 0;
    my $content_field    = MT::ContentField->load($content_field_id);

    return $app->return_to_dashboard( redirect => 1 )
        unless $blog && $content_field->related_content_type_id;

    # TODO: permission check

    my $terms = {
        blog_id         => $blog->id,
        content_type_id => $content_field->related_content_type_id,
    };
    my $args = {
        sort      => 'modified_on',
        direction => 'descend',
    };
    my $hasher = _build_content_data_hasher($app);

    my $dialog    = $app->param('dialog')    ? 1 : 0;
    my $no_insert = $app->param('no_insert') ? 1 : 0;

    $app->listing(
        {   terms    => $terms,
            args     => $args,
            type     => 'cd',
            code     => $hasher,
            template => 'include/content_data_list.tmpl',
            params   => {
                (   $blog
                    ? ( blog_id      => $blog->id,
                        blog_name    => $blog->name || '',
                        edit_blog_id => $blog->id,
                        ( $blog->is_blog ? ( blog_view => 1 ) : () ),
                        )
                    : (),
                ),
                can_multi => $content_field->options->{multiple} ? 1 : 0,
                dialog_view => 1,
                dialog      => $dialog,
                no_insert   => $no_insert,
            },
        }
    );
}

sub _build_content_data_hasher {
    my $app = shift;
    sub {
        my ( $obj, $row, %param ) = @_;

        $row->{id} = $obj->id;
        $row->{title}
            = ( defined $obj->title && $obj->title ne '' )
            ? $obj->title
            : $app->translate( 'No Title (id:[_1])', $obj->id );
        $row->{modified_date} = MT::Util::format_ts( "%Y-%m-%d %H:%M:%S",
            $obj->modified_on, $obj->blog,
            $app->user ? $app->user->preferred_language : undef );
        $row->{author_name}
            = $obj->author
            ? ( $obj->author->nickname || $obj->author->name )
            : $app->translate('*User deleted*');

        $row;
    };
}

sub _validate_content_fields {
    my $app = shift;
    my ( $content_type, $data ) = @_;
    my $content_field_types = $app->registry('content_field_types');

    my @errors;

    foreach my $f ( @{ $content_type->fields } ) {
        my $content_field_type = $content_field_types->{ $f->{type} };
        my $param_name         = 'content-field-' . $f->{id};
        my $d                  = $data->{ $f->{id} };

        if ( exists $f->{options}{required}
            && $f->{options}{required} )
        {
            my $has_data;
            if ( ref $d eq 'ARRAY' ) {
                $has_data = @{$d} ? 1 : 0;
            }
            else {
                $has_data = ( defined $d && $d ne '' ) ? 1 : 0;
            }
            unless ($has_data) {
                my $label = $f->{options}{label};
                push @errors,
                    {
                    field_id => $f->{id},
                    error =>
                        $app->translate(qq{"${label}" field is required.}),
                    };
                next;
            }
        }

        if ( my $ss_validator = $content_field_type->{ss_validator} ) {
            if ( !ref $ss_validator ) {
                $ss_validator = MT->handler_to_coderef($ss_validator);
            }
            if ( 'CODE' eq ref $ss_validator ) {
                if ( my $error = $ss_validator->( $app, $f, $d ) ) {
                    push @errors,
                        {
                        field_id => $f->{id},
                        error    => $error,
                        };
                }
            }
        }
    }

    @errors ? \@errors : undef;
}

sub validate_content_fields {
    my $app = shift;

    # TODO: permission check

    my $blog_id = $app->blog ? $app->blog->id : undef;
    my $content_type_id = $app->param('content_type_id') || 0;
    my $content_type = MT::ContentType->load(
        { id => $content_type_id, blog_id => $blog_id } );

    return $app->json_error( $app->translate('Invalid request.') )
        unless $blog_id && $content_type;

    my $content_field_types = $app->registry('content_field_types');
    my $data                = {};
    foreach my $f ( @{ $content_type->fields } ) {
        my $content_field_type = $content_field_types->{ $f->{type} };
        $data->{ $f->{id} }
            = _get_form_data( $app, $content_field_type, $f );
    }

    my $invalid_count = 0;
    my %invalid_fields;
    if ( my $errors = _validate_content_fields( $app, $content_type ) ) {
        $invalid_count = scalar @{$errors};
        %invalid_fields = map { $_->{field_id} => $_->{error} } @{$errors};
    }

    $app->json_result(
        { invalidCount => $invalid_count, invalidFields => \%invalid_fields }
    );
}

sub content_actions {
    {   new => {
            label => 'Create new content type',
            order => 100,
            mode  => 'cfg_content_type',
            class => 'icon-create',
        }
    };
}

sub list_actions {
    {   delete => {
            label      => 'Delete',
            order      => 100,
            mode       => 'delete',
            button     => 1,
            js_message => 'delete',
        }
    };
}

sub init_content_type {
    my ( $cb, $app ) = @_;
    my $core = $app->component('core');

    my $core_listing_screens         = $core->registry('listing_screens');
    my $content_data_listing_screens = _make_content_data_listing_screens();
    for my $key ( keys %{$content_data_listing_screens} ) {
        $core_listing_screens->{$key} = $content_data_listing_screens->{$key};
    }

    my $core_list_props         = $core->registry('list_properties');
    my $content_data_list_props = MT::ContentData::make_list_props();
    for my $key ( keys %{$content_data_list_props} ) {
        $core_list_props->{$key} = $content_data_list_props->{$key};
    }
}

sub _make_content_data_listing_screens {
    my $props = {};

    my $iter = MT->model('content_type')->load_iter;
    while ( my $ct = $iter->() ) {
        my $key = 'content_data.content_data_' . $ct->id;
        $props->{$key} = {
            primary             => 'title',
            screen_label        => 'Manage ' . $ct->name,
            object_label        => $ct->name,
            object_label_plural => $ct->name,
            object_type         => 'content_data',
            scope_mode          => 'this',
            use_filters         => 0,
            view                => [ 'website', 'blog' ],
            feed_link           => sub {

                # TODO: fix permission
                my ($app) = @_;
                return 1 if $app->user->is_superuser;

                if ( $app->blog ) {
                    return 1
                        if $app->user->can_do( "get_${key}_feed",
                        at_least_one => 1 );
                }
                else {
                    my $iter = MT->model('permission')->load_iter(
                        {   author_id => $app->user->id,
                            blog_id   => { not => 0 },
                        }
                    );
                    my $cond;
                    while ( my $p = $iter->() ) {
                        $cond = 1, last
                            if $p->can_do("get_${key}_feed");
                    }
                    return $cond ? 1 : 0;
                }
                0;
            },
        };
    }

    return $props;
}

sub list_boilerplates {
    my $app = shift;
    my $param
        = { page_title => $app->translate('Manage Content Type Boilerplates'),
        };
    $app->load_tmpl( 'not_implemented_yet.tmpl', $param );
}

1;

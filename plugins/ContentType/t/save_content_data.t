use strict;
use warnings;

use Test::More;

use lib qw( lib extlib t/lib );
use MT::Test qw( :app :db );
use MT::Test::Permission;

use MT::Author;
use MT::ContentData;
use MT::ContentField;
use MT::ContentFieldIndex;
use MT::ContentType;
use MT::Entry;

my $admin = MT::Author->load(1);
my $user  = MT::Test::Permission->make_author;
$user->is_superuser(1);
$user->save or die $user->errstr;

my $content_type = MT::ContentType->new;
$content_type->set_values(
    {   blog_id => 1,
        name    => 'test content type',
    }
);
$content_type->save or die $content_type->errstr;

my $content_field = MT::ContentField->new;
$content_field->set_values(
    {   blog_id         => $content_type->blog_id,
        content_type_id => $content_type->id,
        name            => 'single text',
        type            => 'single_line_text',
    }
);
$content_field->save or die $content_field->errstr;

my $fields = [
    {   id         => $content_field->id,
        label      => 1,
        name       => $content_field->name,
        order      => 1,
        type       => $content_field->type,
        unique_key => $content_field->unique_key,
    }
];
$content_type->fields($fields);
$content_type->save or die $content_type->errstr;

my ( $content_data, $cf_idx );

subtest 'mode=save_content_data (create)' => sub {
    my $app = _run_app(
        'MT::App::CMS',
        {   __test_user                           => $admin,
            __request_method                      => 'POST',
            __mode                                => 'save_content_data',
            blog_id                               => $content_type->blog_id,
            content_type_id                       => $content_type->id,
            status                                => MT::Entry::HOLD(),
            'content-field-' . $content_field->id => 'test input',
        },
    );
    my $out = delete $app->{__test_output};
    ok( $out =~ /saved=1/,   'content data has been saved' );
    ok( $out =~ /302 Found/, 'redirect to list_content_data screen' );

    # check content data
    $content_data = MT::ContentData->load(
        {   blog_id         => $content_type->blog_id,
            author_id       => 1,
            content_type_id => $content_type->id
        }
    );
    ok( $content_data, 'got content data' );
    is( $content_data->column('data'),
        '{"' . $content_field->id . '":"test input"}',
        'content data has content field data'
    );

    is( $content_data->author_id,   $admin->id, 'author_id is admin ID' );
    is( $content_data->created_by,  $admin->id, 'created_by is admin ID' );
    is( $content_data->modified_by, undef,      'modified_by is undef' );

    # check content field
    $cf_idx = MT::ContentFieldIndex->load(
        {   content_type_id  => $content_type->id,
            content_field_id => $content_field->id,
            content_data_id  => $content_data->id,
        }
    );
    ok( $cf_idx, 'got content field index' );
    is( $cf_idx->value_varchar, 'test input',
        'content field data is set in content field index' );
};

subtest 'mode=save_content_data (update)' => sub {
    my $app = _run_app(
        'MT::App::CMS',
        {   __test_user                           => $user,
            __request_method                      => 'POST',
            __mode                                => 'save_content_data',
            id                                    => $content_data->id,
            blog_id                               => $content_type->blog_id,
            content_type_id                       => $content_type->id,
            status                                => MT::Entry::HOLD(),
            'content-field-' . $content_field->id => 'test input update',
        },
    );
    my $out = delete $app->{__test_output};
    ok( $out =~ /saved=1/,   'content data has been saved' );
    ok( $out =~ /302 Found/, 'redirect to list_content_data screen' );

    # check content data
    is( MT::ContentData->count, 1, 'content data count is 1' );
    is( MT::ContentData->load->id,
        $content_data->id, 'content data ID is not changed' );

    $content_data = MT::ContentData->load( $content_data->id );
    is( $content_data->column('data'),
        '{"' . $content_field->id . '":"test input update"}',
        'content field data has been updated'
    );

    is( $content_data->author_id,   $admin->id, 'author_id is admin ID' );
    is( $content_data->created_by,  $admin->id, 'created_by is admin ID' );
    is( $content_data->modified_by, $user->id,  'modified_by is user ID' );

    # check content field
    is( MT::ContentFieldIndex->count, 1, 'content field count is 1' );
    is( MT::ContentFieldIndex->load->id,
        $cf_idx->id, 'content field ID is not changed' );

    $cf_idx = MT::ContentFieldIndex->load( $cf_idx->id );
    is( $cf_idx->value_varchar,
        'test input update',
        'content field data has been updated in content field index'
    );
};

done_testing;


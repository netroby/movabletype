#!/usr/bin/perl

# Movable Type (r) (C) 2001-2017 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id: driver-tests.pl 3531 2009-03-12 09:11:52Z fumiakiy $

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib"; # t/lib
use Test::More;
use MT::Test::Env;
our $test_env;
BEGIN {
    $test_env = MT::Test::Env->new;
    $ENV{MT_CONFIG} = $test_env->config_file;
}

use Test::More;
use lib 't/lib';

BEGIN {
    $ENV{MT_CONFIG} = 'mysql-test-disable-object-cache.cfg';
    plan skip_all => "Configuration file $ENV{MT_CONFIG} not found"
        if !-r "t/$ENV{MT_CONFIG}";

    my $module = 'DBD::mysql';
    eval "require $module;";
    plan skip_all => "Database driver '$module' not found."
        if $@;
}

use MT::Test::Driver;

Test::Class->runtests;

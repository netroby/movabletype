<?php
# Movable Type (r) Open Source (C) 2001-2011 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$

require_once('block.mtentryiftagged.php');
function smarty_block_mtpageiftagged($args, $content, &$ctx, &$repeat) {
    $args['class'] = 'page';
    return smarty_block_mtentryiftagged($args, $content, $ctx, $repeat);
}
?>

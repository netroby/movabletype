<?php
# Movable Type (r) (C) 2001-2018 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

function smarty_block_mtcontentfield($args, $res, &$ctx, &$repeat) {
    $localvars = array(
        array('ContentFieldHeader','ContentFieldFooter','content_field_type','content_field_data'),
        array('_content_field_counter','_content_field_counter_max','_content_field_values', '_content_field_data'),
        array('Tag','tag_count','tag_content_count'),
        array('_assets'),
        array('category','entries','contents','category_count','blog_id','blog'),
        array('parent_content','parent_content_type','content','content_type','contents'),
        array('conditonal','else_content'),
        common_loop_vars()
    );

    if (!isset($res)) {
        $ctx->localize($localvars);
        $counter = 0;
        $ctx->stash('_content_field_counter', $counter);
        $ctx->stash('_content_field_counter_max', 0);
        $ctx->stash('_content_field_values', array());
        $ctx->stash('ContentFieldHeader', 0);
        $ctx->stash('ContentFieldFooter', 0);
        $ctx->stash('conditional', 1);
        $counter_max = 1;

        require_once('multiblog.php');
        multiblog_block_wrapper($args, $res, $ctx, $repeat);

        require_once('content_field_type_lib.php');
    } else {
        $counter = $ctx->__stash['_content_field_counter'];
        if (!$counter) $counter = 0;

        $counter_max = $ctx->stash('_content_field_counter_max');
        if (!$counter_max) $counter_max = 0;
    }

    if ($counter < $counter_max) {
        $content_type = $ctx->stash('content_type');
        if (!is_object($content_type))
            return $ctx->error($ctx->mt->translate('No Content Type could be found.') );

        $content_data = $ctx->stash('content');
        if (!is_object($content_data))
            return $ctx->error($ctx->mt->translate(
                "You used an '[_1]' tag outside of the context of a content; Perhaps you mistakenly placed it outside of an 'MTContents' container tag?", "mtContentField" ));

        $content_fields = $content_type->fields;
        if (isset($content_fields)) {
            $content_fields = $ctx->mt->db()->unserialize($content_fields);
        }

        if (isset($args['content_field'])) {
            $field_id = $args['content_field'];
            if (preg_match('/^[0-9]+$/', $field_id)) {
                $field_data = array_filter($content_fields, function($f) use ($field_id) {
                    return $f['id'] == $field_id;
                });
            }
            if (empty($field_data)) {
                $field_data = array_filter($content_fields, function($f) use ($field_id) {
                    return (isset($f['unique_id']) && ($f['unique_id'] == $field_id));
                });
            }
            if (empty($field_data)) {
                $field_data = array_filter($content_fields, function($f) use ($field_id) {
                    return (isset($f['name']) && ($f['name'] == $field_id));
                });
            }
            if (empty($field_data)) {
                $field_data = array_filter($content_fields, function($f) use ($field_id) {
                    return (isset($f['options']['label']) && ($f['options']['label'] == $field_id));
                });
            }
            if (!empty($field_data) && is_array($field_data)) {
                $field_data = array_shift($field_data);
            }
        }

        if (!$field_data) {
            $field_data = $ctx->stash('content_field_data');
            if (!$field_data && !$args['content_field']) {
                $field_data = $content_fields[0];
            }
            if (!$field_data) {
                return $ctx->error($ctx->mt->translate("No Content Field could be found."));
            }
        }

        $ctx->stash('_content_field_data', $field_data);
        if (!$ctx->stash('content_field_data')) {
            $ctx->stash('content_field_data', $field_data);
        }

        $value = $content_data->data;
        if (isset($value)) {
            $value = $ctx->mt->db()->unserialize($value);
            $value = $value[$field_data['id']];
        }
        if (is_array($value) ? (empty($value) || !$value[0]) : !$value) {
            $ctx->stash('conditional', 0);
            $ctx->stash('_content_field_counter', $counter + 1);
            $repeat = true;
            return $res;
        }

        $field_type = ContentFieldTypeFactory::get_type($field_data['type']);
        if (!$field_type) {
            return $ctx->error($ctx->mt->translate("No Content Field Type could be found."));
        }

        $ctx->stash('content_field_type', $field_type);

        $field_type->tag_handler($value, $args, $res, $ctx, $repeat);
        $ctx->stash('_content_field_counter', $counter + 1);
        $repeat = true;
    } else {
        $ctx->restore($localvars);
        $repeat = false;
    }

    return $res;
}
?>
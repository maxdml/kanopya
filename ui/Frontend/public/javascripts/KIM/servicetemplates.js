require('common/notification_subscription.js');
require('common/service_common.js');

function load_service_template_content (container_id) {
    function createAddServiceTemplateButton(cid, grid) {
        var button = $("<button>", { html : 'Add a service'} ).button({
            icons   : { primary : 'ui-icon-plusthick' }
        });

        button.bind('click', function() {
            // Use the kanopyaformwizard for policies
            (new KanopyaFormWizard({
                title         : 'Add a service',
                type          : 'servicetemplate',
                reloadable    : true,
                displayed     : [ 'service_name', 'service_desc' ],
                attrsCallback : function (resource, data, reloaded) {
                    var args = {
                        params  : data,
                        trigger : reloaded
                    };
                    var attributes = ajax('POST', '/api/attributes/' + resource, args);

                    // Set steps
                    set_steps(attributes);

                    // Set the value if defined (at reload)
                    $.each([ 'service_name', 'service_desc' ], function (index, attr) {
                        if (data[attr] !== undefined) {
                            attributes.attributes[attr].value = data[attr];
                        }
                    });
                    return attributes;
                },
                callback : function () { grid.trigger("reloadGrid"); }
            })).start();
        });
        var action_div=$('#' + cid).prevAll('.action_buttons');
        action_div.append(button);
    };

    var container = $('#' + container_id);
    var grid = create_grid( {
        url: '/api/servicetemplate',
        content_container_id: container_id,
        grid_id: 'service_template_list',
        colNames: [ 'ID', 'Name', 'Description', '' ],
        colModel: [ { name: 'service_template_id', index:'service_template_id', width:60, sorttype:"int", hidden:true, key:true},
                    { name: 'service_name', index: 'service_name', width:300 },
                    { name: 'service_desc', index: 'service_desc', width:500 },
                    { name: 'subscribe', index : 'subscribe', width : 40, align : 'center', nodetails : true }],
        afterInsertRow: function(grid, rowid, rowdata, rowelem) {
            require('common/notification_subscription.js');
            addSubscriptionButtonInGrid(grid, rowid, rowdata, rowelem, "service_template_list_subscribe", "AddCluster");
        }
    } );

    if (current_user_has_any_profiles([ "Administrator", "Services Developer" ])) {
        createAddServiceTemplateButton(container_id, grid);
    }
}

function load_service_template_details (elem_id, row_data, grid_id) {
    // USe a rax attr def for the service template update,
    // we dont want to edit policies contents, only policies ids
    (new KanopyaFormWizard({
        title     : 'Edit service template: ' + row_data.service_name,
        id        : elem_id,
        type      : 'servicetemplate',
        displayed : [ 'service_name', 'service_desc', 'hosting_policy_id', 'storage_policy_id', 'network_policy_id',
                      'scalability_policy_id', 'system_policy_id', 'billing_policy_id', 'orchestration_policy_id' ],
        rawattrdef   : {
            service_name : {
                label        : 'Service name',
                type         : 'string',
                is_mandatory : 1,
                is_editable  : 1
            },
            service_desc : {
                label        : 'Description',
                type         : 'text',
                is_mandatory : 0,
                is_editable  : 1
            },
            hosting_policy_id : {
                label        : 'Hosting policy',
                type         : 'relation',
                relation     : 'single',
                is_mandatory : 1,
                is_editable  : 1
            },
            storage_policy_id : {
                label        : 'Storage policy',
                type         : 'relation',
                relation     : 'single',
                is_mandatory : 1,
                is_editable  : 1
            },
            network_policy_id : {
                label        : 'Network policy',
                type         : 'relation',
                relation     : 'single',
                is_mandatory : 1,
                is_editable  : 1
            },
            scalability_policy_id : {
                label        : 'Scalability policy',
                type         : 'relation',
                relation     : 'single',
                is_mandatory : 1,
                is_editable  : 1
            },
            system_policy_id : {
                label        : 'System policy',
                type         : 'relation',
                relation     : 'single',
                is_mandatory : 1,
                is_editable  : 1
            },
            billing_policy_id : {
                label        : 'Billing policy',
                type         : 'relation',
                relation     : 'single',
                is_mandatory : 1,
                is_editable  : 1
            },
            orchestration_policy_id : {
                label        : 'Orchestration policy',
                type         : 'relation',
                relation     : 'single',
                is_mandatory : 1,
                is_editable  : 1
            }
        },
        optionsCallback : function(name) {
            var type = name.match(/(.*)_policy_id/);
            if (type.length == 2) {
                var policies = ajax('GET', '/api/policy?policy_type=' + type[1]);
                return policies;
            }
            return false;
        },
        attrsCallback : function (resource, data, reloaded) {
            return { attributes : {}, relations : {} };;
        },
        callback : function () { $('#' + grid_id).trigger("reloadGrid"); }
    })).start();
}

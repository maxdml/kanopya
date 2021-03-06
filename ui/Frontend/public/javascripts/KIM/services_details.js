require('common/general.js');
require('common/service_common.js');

function loadServicesDetails(cid, eid, is_iaas) {
    var divId = 'service_details';
    var container = $('#'+ cid);
    if (container.prevAll('.action_buttons').length === 0) {
        container.before('<div class="action_buttons"></div>');
    }
    var table = $("<tr>").appendTo($("<table>").css('width', '100%').appendTo(container));
    var div   = $('<div>', { id: divId}).appendTo($("<td>").appendTo(table));
    $('<h4>Details</h4>').appendTo(div);

    // Keep the detai form as it will be used in action button callbacks
    var form;

    var components = [];
    function scaleOutComponentsDialog (e) {
        var installed_types = {};
        for (var index in components) {
            installed_types[components[index].component_type.pk] = components[index].component_type.component_name;
        }

        // Open a wizards to suggest component type to scale to the user
        (new KanopyaFormWizard({
            title      : 'Scale out components',
            displayed  : [ 'component_types' ],
            rawattrdef : {
                component_types : {
                    label        : 'Components to scale out',
                    type         : 'relation',
                    relation     : 'multi',
                    is_mandatory : 1,
                    options      : installed_types
                }
            },
            submitCallback  : function(data, $form, opts, onsuccess, onerror) {
                ajax('POST', '/api/cluster/' + eid + '/addNode', data, onsuccess, onerror);
            }
        })).start();
    }

    function removeClusterDialog (e) {
        // Open a wizards to suggest component type to scale to the user
        (new KanopyaFormWizard({
            title      : 'Remove cluster',
            displayed  : [ 'keep_systemimages' ],
            rawattrdef : {
                keep_systemimages : {
                    label        : 'Keep the cluster system images',
                    type         : 'boolean',
                    is_mandatory : 1
                }
            },
            submitCallback  : function(data, $form, opts, onsuccess, onerror) {
                ajax('POST', '/api/cluster/' + eid + '/remove', data, onsuccess, onerror);
            }
        })).start();
    }

    function editCluster (e) {
        // Open a wizards to suggest component type to scale to the user
        var button = e.target;
        var span = button.parent;

        $(button).attr('disabled', 'disabled')
        if ($(button).text() == 'Edit service') {
            // Set the editable mode
            form.noStateDisabled = false;
            form.reload();

            $(button).text('Save changes');

        } else {
            // Validate the form
            form.validateForm();

            $(button).text('Edit service');

            $("#" + divId).empty();
            displayDetails();
        }
        $(button).removeAttr("disabled");
    }

    function displayDetails () {
        $("#" + divId).append('<div class="loading"><img alt="Loading, please wait" src="/css/theme/loading.gif" /><p>Loading...</p></div>');
        $.ajax({
            url     : '/api/cluster/' + eid + '?expand=interfaces.netconfs,components.component_type,billinglimits,' +
                      'service_provider_managers.manager_category,service_provider_managers.param_preset',
            async   : true,
            success : function(details) {
                // If this sp is a Iaas, we get its cloud manager component id (used for optimiaas)
                var cloudmanager_id;

                //var actioncell  = $('<td>', {'class' : 'action-cell'}).css('text-align', 'right').appendTo(table);
                var actioncell = $('#' + cid).prevAll('.action_buttons');

                var buttons = [
                    {
                        label       : 'Edit service',
                        sprite      : 'pencil',
                        action      : editCluster,
                        condition   : (new RegExp('^down')).test(details.cluster_state)
                    },
                    {
                        label       : 'Start instance',
                        sprite      : 'start',
                        action      : '/api/cluster/' + eid + '/start',
                        condition   : (new RegExp('^down')).test(details.cluster_state),
                        confirm     : 'This will start your instance'
                    },
                    {
                        label       : 'Stop instance',
                        sprite      : 'stop',
                        action      : '/api/cluster/' + eid + '/stop',
                        condition   : (new RegExp('^up')).test(details.cluster_state),
                        confirm     : 'This will stop all your running instances'
                    },
                    {
                        label       : 'Force stop instance',
                        sprite      : 'stop',
                        action      : '/api/cluster/' + eid + '/forceStop',
                        condition   : (!(new RegExp('^down')).test(details.cluster_state)),
                        confirm     : 'This will stop all your running instances'
                    },
                    {
                        label       : 'Scale out',
                        icon        : 'arrowthick-2-e-w',
                        action      : '/api/cluster/' + eid + '/addNode'
                    },
                    {
                        label       : 'Scale out components',
                        icon        : 'arrowthick-2-e-w',
                        action      : scaleOutComponentsDialog
                    },
                    {
                        label       : 'Optimize IaaS',
                        icon        : 'calculator',
                        action      : '/api/component/' + cloudmanager_id + '/optimiaas',
                        condition   : is_iaas !== undefined
                    },
                    {
                        label       : 'Remove',
                        icon        : 'trash',
                        action      : removeClusterDialog
                    }
                ];
                if (actioncell.find('span').length === 0) {
                    createallbuttons(buttons, actioncell);
                }

                // Remove some fields because the api will unserialize this params as an object
                delete details.class_type_id;
                delete details.pk;

                /*
                 * Format the values as the cluster json do not exactly fit to the service template def.
                 */

                // Make an array of netconfs id instead of array of netconf object
                if ($.isArray(details.interfaces)) {
                    for (var index in details.interfaces) {
                        if ($.isArray(details.interfaces[index].netconfs)) {
                            var netconfs = [];
                            for (var index_netconfs in details.interfaces[index].netconfs) {
                                netconfs.push(details.interfaces[index].netconfs[index_netconfs].pk);
                            }
                            details.interfaces[index].netconfs = netconfs;
                        }
                    }
                }

                // Change the billing limit attr name
                if ($.isArray(details.billinglimits)) {
                    details.billing_limits = details.billinglimits;
                    delete details.billinglimits;
                }

                // Store the cluster component list for "Scale out component" action
                jQuery.extend(true, components, details.components);

                // Change the component_type attr name
                if ($.isArray(details.components)) {
                    for (var index in details.components) {
                        details.components[index].component_type = details.components[index].component_type_id;
                    }
                }

                // Add managers ids as cluster attributes
                if ($.isArray(details.service_provider_managers)) {
                    var managers = details.service_provider_managers;
                    delete details.service_provider_managers;
                    for (var index in managers) {
                        var category = managers[index].manager_category.category_name;
                        if (category == 'HostManager' && is_iaas) {
                            cloudmanager_id = managers[index].manager_id;
                        }
                        var manager_attr_name = category.replace('Manager', '').toLowerCase() + "_manager_id";
                        details[manager_attr_name] = managers[index].manager_id;
                        // Handle manager params
                        if ($.isPlainObject(managers[index].param_preset) && managers[index].param_preset.params != undefined) {
                            $.extend(true, details, JSON.parse(managers[index].param_preset.params));
                        }
                    }
                }

                $('.loading').remove();

                $("#" + divId).append((form = new KanopyaFormWizard({
                    title           : 'Service details',
                    type            : 'cluster',
                    id              : eid,
                    reloadable      : true,
                    hideDisabled    : false,
                    stepsAsTags     : true,
                    noStateDisabled : true,
                    displayed       : [ 'cluster_name', 'cluster_desc', 'owner_id', 'service_template_id' ],
                    rawattrdef      : {
                        cluster_name : {
                            label        : 'Instance name',
                            type         : 'string',
                            pattern      : '^[a-zA-Z_0-9]+$',
                            size         : 200,
                            is_mandatory : true,
                            is_editable  : false
                        },
                        cluster_desc : {
                            label        : 'Instance description',
                            type         : 'text',
                            pattern      : '^.*$',
                            is_mandatory : false,
                            is_editable  : true
                        },
                        owner_id : {
                            label        : 'Customer',
                            type         : 'relation',
                            relation     : 'single',
                            pattern      : "^[1-9][0-9]+$",
                            is_mandatory : true,
                            is_editable  : false
                        },
                        service_template_id : {
                            label        : 'Service type',
                            type         : 'relation',
                            relation     : 'single',
                            reload       : true,
                            pattern      : "^[1-9][0-9]+$",
                            welcome      : "Select a service type",
                            is_mandatory : true,
                            is_editable  : false
                        }
                    },
                    attrsCallback : function (resource, data, trigger) {
                        var attributes;

                        // Define the cluster relation hard coded here, to avoid a call
                        // to the cluster attributes for the relations only
                        var cluster_relations = {
                            owner : {
                                resource : "user",
                                cond     : { "foreign.user_id" : "self.owner_id" },
                                attrs    : { accessor : "single" }
                            },
                            service_template : {
                                resource : "servicetemplate",
                                cond     : { "foreign.service_template_id" : "self.service_template_id" },
                                attrs    : { accessor : "single" }
                            }
                        };

                        // If the service template defined, fill the form with the service template definition
                        var args = { params : details, trigger : trigger };
                        attributes = ajax('POST', '/api/attributes/servicetemplate', args);

                        // Delete the service template fields other than policies ids
                        delete attributes.attributes['service_name'];
                        delete attributes.attributes['service_desc'];

                        if (this.noStateDisabled == false) {
                            $.extend(true, attributes.attributes, ajax('GET', '/api/attributes/cluster').attributes);
                        }
                        $.extend(true, attributes.relations, cluster_relations);

                        // Set steps
                        set_steps(attributes, this.noStateDisabled == true ? 0 : undefined);

                        // Filter displayed fields
                        attributes.displayed = $.grep(attributes.displayed, function(n, i) {
                                                   if ($.isPlainObject(n)) {
                                                       if (n.components !== undefined) {
                                                           // Remove the component list as component ha specific management
                                                           return false;
                                                       }
                                                   } else if (n.match(/_policy_id$/) != undefined) {
                                                        // Do not display policies
                                                        return false;
                                                   }
                                                   return true;
                                               });

                        // Set the value if defined (at reload)
                        $.each([ 'cluster_name', 'cluster_desc', 'owner_id', 'service_template_id' ], function (index, attr) {
                            if (details[attr] !== undefined) {
                                if (attributes.attributes[attr] === undefined) {
                                    attributes.attributes[attr] = {};
                                }
                                attributes.attributes[attr].value = details[attr];
                            }
                        });
                        return attributes;
                    },
                    valuesCallback : function(type, id, attributes) {
                        return details;
                    },
                    submitCallback : function(data, $form, opts, onsuccess, onerror) {
                        // Manually add the service_template_id as it is deisabled in the form
                        data.service_template_id = details.service_template_id;

                        // Manually update the cluster
                        return ajax('PUT', '/api/cluster/' + eid, data, onsuccess, onerror);
                    }
                })).start(true));
            }
        });
    }
    displayDetails();
}

function createallbuttons(buttons, container) {
    for (var i in buttons) if (buttons.hasOwnProperty(i)) {
        if (buttons[i].condition === undefined || buttons[i].condition) {
            $(container).append(createbutton(buttons[i]));
            
        }
    }
}

function createbutton(button) {
    var class_span_button=(button.sprite ?'button-with-sprite':'button-without-sprite');
    return $('<span class="'+class_span_button+'"></span>').append(
               $('<span class="' +
                 (button.sprite ?
                     'kanopya-sprite kanopya-button-sprite ui-icon-' + button.sprite :
                     'ui-icon-' + button.icon) + '"></span>')
           ).append(
               $('<a>', { text : button.label })
           ).button().bind('click', function (e) {
                if (button.confirm && !confirm(button.confirm + ". Do you want to continue ?")) {
                    return false;
                }
                if (typeof(button.action) === 'string') {
                    $.ajax({
                        url         : button.action,
                        type        : 'POST',
                        contentType : 'application/json',
                        data        : JSON.stringify((button.data !== undefined) ? button.data : {})
                    });
                } else {
                    button.action(e);
                }
    });
}

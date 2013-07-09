require('KIM/services.js');

/* Temporary redefinition of a nested function of KIM/services.js */
function NodeIndicatorDetailsHistorical(cid, node_id, elem_id) {
    var cont = $('#' + cid);
    var graph_div = $('<div>', { 'class' : 'widgetcontent' });
    cont.addClass('widget');
    cont.append(graph_div);
    graph_div.load('/widgets/widget_historical_node_indicator.html', function() {
        initNodeIndicatorWidget(cont, elem_id, node_id);
    });
}

function vmdetails(spid) {
    return {
        tabs : [
            { label : 'General', id : 'generalnodedetails', onLoad : nodedetailsaction },
            { label : 'Network Interfaces', id : 'iface', onLoad : function(cid, eid) {node_ifaces_tab(cid, eid); } },
            { label : 'Monitoring', id : 'resource_monitoring', onLoad : function(cid, eid) { NodeIndicatorDetailsHistorical(cid, eid, spid); } },
            { label : 'Rules', id : 'rules', onLoad : function(cid, eid) { node_rules_tab(cid, eid, spid); } },
        ],
        title : { from_column : 'node_hostname' }
    };
}

function load_iaas_detail_hypervisor (container_id, elem_id) {
    var container = $('#' + container_id);

    // Retrieve the cloud manager
    var cloudmanagerid;
    $.ajax({
        url     : 'api/serviceprovider/'+elem_id+'/components?component_type.component_type_categories.component_category.category_name=HostManager',
        async   : false,
        success : function(host_manager) {
           cloudmanagerid = host_manager[0].pk;
        }
    });
    if (cloudmanagerid == null) {
        console.log('No cloud manager found');
        return;
    }

    $.ajax({
        url     : '/api/virtualization/' + cloudmanagerid + '/hypervisors?expand=node',
        type    : 'POST',
        success : function(data) {
            var topush  = [];
            for (var i in data) if (data.hasOwnProperty(i)) {
                data[i].id      = data[i].pk;
                data[i].parent  = null;
                data[i].level   = '0';
                data[i].type    = 'hypervisor';
                data[i].vmcount = 0;
                $.ajax({
                    async   : false,
                    url     : '/api/hypervisor/' + data[i].id + '/virtual_machines?expand=node',
                    success : function(hyp) {
                        return (function(vms) {
                            hyp.totalRamUsed    = 0;
                            hyp.totalCoreUsed   = 0;
                            if (vms.length > 0) {
                                hyp.vmcount     += vms.length
                                hyp.isLeaf      = false;
                                for (var j in vms) if (vms.hasOwnProperty(j)) {
                                    vms[j].id       = hyp.id + "_" + vms[j].pk;
                                    vms[j].isLeaf   = true;
                                    vms[j].level    = '1';
                                    vms[j].parent   = hyp.id;
                                    vms[j].type     = 'vm';
                                    hyp.totalRamUsed    += parseInt(vms[j].host_ram);
                                    hyp.totalCoreUsed   += parseInt(vms[j].host_core);
                                    topush.push(vms[j]);
                                }
                            } else {
                                hyp.isLeaf  = true;
                            }
                        });
                    }(data[i])
                });
            }
            data    = data.concat(topush);
            createTreeGrid({
                caption                 : 'Hypervisors for IaaS ' + elem_id,
                treeGrid                : true,
                treeGridModel           : 'adjacency',
                ExpandColumn            : 'node.node_hostname',
                data                    : data,
                content_container_id    : container_id,
                grid_id                 : 'iaas_hyp_list',
                colNames                : [ 'ID', 'Base hostname', 'State', 'Vms', 'Admin Ip', '', '', '', '', '', '' ],
                colModel                : [
                    { name : 'id', index : 'id', width : 60, sorttype : "int", hidden : true, key : true },
                    { name : 'node.node_hostname', index : 'node.node_hostname', width : 90 },
                    { name : 'host_state', index : 'host_state', width : 30, formatter : StateFormatter, align : 'center' },
                    { name : 'vmcount', index : 'vmcount', width : 30, align : 'center' },
                    { name : 'adminip', index : 'adminip', width : 100 },
                    { name : 'totalRamUsed', index : 'totalRamUsed', hidden : true },
                    { name : 'host_ram', index : 'host_ram', hidden : true },
                    { name : 'type', index : 'type', hidden : true },
                    { name : 'entity_id', index : 'entity_id', hidden : true },
                    { name : 'host_core', index : 'host_core', hidden : true },
                    { name : 'totalCoreUsed', index : 'totalCoreUsed', hidden : true }
                ],
                action_delete           : 'no',
                gridComplete            : displayAdminIps,
                details                 : {
                    tabs    : [
                        {
                            label   : 'Overview',
                            id      : 'hypervisor_detail_overview',
                            onLoad  : function(cid, eid) { load_hypervisorvm_details(cid, eid, cloudmanagerid); }
                        },
                        {
                            label  : 'General',
                            id     : 'generalnodedetails',
                            onLoad : function(cid, eid) { nodedetailsaction(cid, null, eid); }
                        },
                        {
                            label  : 'Network Interfaces',
                            id     : 'iface',
                            onLoad : function(cid, eid) { node_ifaces_tab(cid, null, eid); }
                        },
                    ],
                    title : { from_column : 'node.node_hostname' }
                },
            }, 10);
        }
    });
}

function displayAdminIps() {
    var grid    = $('#iaas_hyp_list');
    var dataIds = $(grid).jqGrid('getDataIDs');
    for (var i in dataIds) if (dataIds.hasOwnProperty(i)) {
        var rowData = $(grid).jqGrid('getRowData', dataIds[i]);
        $.ajax({
            url     : '/api/host/' + rowData.entity_id,
            type    : 'GET',
            success : function(grid, rowid) {
                return function(data) {
                    $(grid).jqGrid('setCell', rowid, 'adminip', data.admin_ip);
                };
            }(grid, dataIds[i])
        });
    }
}

function load_hypervisorvm_details(cid, eid, cmgrid) {
    var data            = $('#iaas_hyp_list').jqGrid('getRowData', eid);
    if (data.type === 'hypervisor') {
        var table           = $('<table>', { width : '100%' }).appendTo($('#' + cid));
        $(table).append($('<tr>').append($('<th>', { text : 'Hostname : ', width : '100px' }))
                                     .append($('<td>', { text : data['node.node_hostname'] })));
        data.host_ram = data.host_ram / 1024 / 1024;
        data.totalRamUsed = data.totalRamUsed / 1024 / 1024;
        var hypervisorType  = $('<td>');
        $(table).append($('<tr>').append($('<th>', { text : 'Hypervisor : ' }))
                                 .append(hypervisorType))
                .append($('<tr>').append($('<th>', { text : 'RAM Used : ' }))
                                 .append($('<td>').append($('<div>').progressbar({ max : data.host_ram, value : data.totalRamUsed }))
                                                  .append($('<span>', { text : data.totalRamUsed + ' / ' + data.host_ram + ' Mo', style : 'float:right;' }))))
                .append($('<tr>').append($('<th>', { text : 'Cpu Used : ' }))
                                 .append($('<td>').append($('<div>').progressbar({ max : data.host_core, value : parseInt(data.totalCoreUsed) }))
                                                  .append($('<span>', { text : data.totalCoreUsed + ' / ' + data.host_core, style : 'float:right;' }))));
        $.ajax({
            url     : '/api/entity/' + cmgrid,
            success : function(elem) { $(hypervisorType).text(elem.hypervisor); }
        });
    }
    else {
        $('#' + cid).parents('.ui-dialog').first().find('button').first().trigger('click');
        $.ajax({
            url     : '/api/host/' + data.entity_id + '?expand=node',
            success : function(node) {
                node    = node.node;
                show_detail('iaas_hyp_list', $('#iaas_hyp_list').attr('class'), node.pk, node, vmdetails(node.service_provider_id));
            }
        });
    }
}

function load_iaas_content (container_id) {
    require('common/formatters.js');

    var tabs = [];
    // Add the same tabs than 'Services'
    jQuery.extend(true, tabs, mainmenu_def.Services.jsontree.submenu);
    // Remove the Billing tab
    for (var i = tabs.length -1; i >= 0; i--) {
        if (tabs[i].id == 'billing') {
            tabs.splice(i,1);
            break;
        }
    }
    // Add the tab 'Hypervisor'
    tabs.push({label : 'Hypervisors', id : 'hypervisors', onLoad : load_iaas_detail_hypervisor, icon : 'compute'});
    // change details tab callback to inform we are in IAAS mode
    var details_tab = $.grep(tabs, function (e) {return e.id == 'service_details'});
    details_tab[0].onLoad = function(cid, eid) { require('KIM/services_details.js'); loadServicesDetails(cid, eid, 1);};

    // Get cluster
    var url = '/api/cluster';
    // Only cluster with a component of category 'HostManager'
    url += '?components.component_type.component_type_categories.component_category.category_name=HostManager';
    // Need component_type info to filter during afterInsertRow() callback
    url += '&expand=components.component_type&deep=1';
    // Exclude kanopya cluster
    url += '&cluster_id=<>,' + kanopya_cluster;

    create_grid({
        url : url,
        content_container_id    : container_id,
        grid_id                 : 'iaas_list',
        colNames                : [ 'ID', 'Name', 'State', 'Active' ],
        colModel                : [
            { name : 'pk', index : 'pk', width : 60, sorttype : 'int', hidden : true, key : true },
            { name : 'cluster_name', index : 'cluster_name', width : 200 },
            { name : 'cluster_state', index : 'cluster_state', width : 200, formatter : StateFormatter },
            { name: 'active', index: 'active', hidden : true}
        ],
        afterInsertRow : function(grid, rowid, rowdata, rowelem) {
            // Keep only instance where the component implementing HostManager manage hosts of type 'Virtual Machine'
            // 'host_type' is a virtual attribute and so can not be filtered in the request
            for (var i in rowelem.components) {
                if (rowelem.components[i].host_type === 'Virtual Machine') {
                    return true;
                }
            }
            $(grid).jqGrid('delRowData', rowid);
        },
        details                 : {
            noDialog    : true,
            tabs        : tabs
        },
        deactivate  : true,
    });
}

require('widgets/widget_common.js');
require('jquery/jquery.multiselect.filter.min.js');

$('.widget').live('widgetLoadContent',function(e, obj){
    // Check if loaded widget is for us
    if (obj.widget.element.find('.clusterCombinationView').length == 0) {return;}

    setGraphDatePicker(obj.widget.element, obj.widget);
    widgetCommonInit(obj.widget.element);

    var sp_id = obj.widget.metadata.service_id;
    initWidget(
        obj.widget,
        sp_id
    );

    obj.widget.element.find('.widget_part_forcasting').hide();
});

function initWidget(widget, sp_id) {
    fillServiceMetricCombinationList (widget, sp_id);
    InitNodeMetricControl(widget, sp_id);
}

/*
 * Tiny dirty cache
 * Allow widget instances to share basic requests result
 * Only for get request without parameters
 * Do not manage error status
 *
 * Note: Not the good way to do $.ajax caching
 * TODO Cache properly
 */
var _requestCache = {};
function getCache(url, callback) {
    var now = Date.now();
    var resp = _requestCache[url];
    if (resp && (now - resp.time) < 20000) {
        callback(resp.data);
    } else {
        if (resp && resp.pending) {
            resp.listeners.push(callback);
        } else {
            _requestCache[url] = {
                    pending   : true,
                    listeners : [callback]
            }
            $.get(url, function(data) {
                var listeners = _requestCache[url].listeners;
                _requestCache[url] = {
                        time     : now,
                        data     : data,
                };
                $.each(listeners, function(i, callback) {
                    callback(data);
                })
            })
        }
    }
}

function InitNodeMetricControl(widget, sp_id) {
    getCache('/api/nodemetriccombination?service_provider_id=' + sp_id, function (data) {
        var nodemetriccombination_list = widget.element.find('.nodemetriccombination_list').css('width', '250px');
        $(data).each( function () {
            nodemetriccombination_list.append($('<option>', {
                combi_id: this.pk,
                value   : this.label,
                text    : this.label,
                unit    : this.combination_unit
            }));
        });
        nodemetriccombination_list.multiselect({
            noneSelectedText: 'Select node combinations',
            selectedText    : "# selected node combinations",
            selectedList    : 1,
            height          : '200px !important',
            width           : '300px'
        })
        .multiselectfilter();
    });

    getCache('/api/serviceprovider/'+sp_id+'/nodes?monitoring_state=<>,disabled', function (data) {
        var node_list = widget.element.find('.node_list');
        $(data).each( function () {
            node_list.append($('<option>', {
                node_id : this.pk,
                value   : this.node_hostname,
                text    : this.node_hostname,
            }));
        });
        node_list.multiselect({
            noneSelectedText: 'Select nodes',
            selectedText    : "# selected nodes",
            selectedList    : 1,
            height          : '200px !important'
        })
        .multiselectfilter();
    });
}

function fillServiceMetricCombinationList (widget, sp_id) {
    var indic_list = widget.element.find('.servicecombination_list').css('width', '250px');

    setRefreshButton(widget, null, sp_id);

    getCache('/api/aggregatecombination?service_provider_id=' + sp_id, function (data) {
        $(data).each( function () {
            // We do not set attr 'id' to avoid multiselect conflit when there is several instance of this widget
            indic_list.append($('<option>', {
                combi_id: this.pk,
                value   : this.label,
                text    : this.label,
                unit    : this.combination_unit
            }));
        });

        // Load widget content if configured
        if (widget.metadata.aggregate_combination_ids) {
            // Select combinations in drop down list
            var selected_ids = widget.metadata.aggregate_combination_ids.split(',');
            $.each(selected_ids, function(i,id) {
                indic_list.find('option[combi_id=' + id+']').prop('selected', true).val();
            });
            widget.element.find('.refresh_button').click();
        }

        indic_list.multiselect({
            noneSelectedText: 'Select service combinations',
            selectedText    : "# selected service combinations",
            selectedList    : 1,
            height          : '200px !important'
        })
        .multiselectfilter();
    });
}

function _getSelectedCombinations(widget_div, list_class) {
    return $.map(
               widget_div.find('.'+list_class+' option:selected'),
               function(elem) {
                   return {
                           id  : $(elem).attr('combi_id'),
                           name: $(elem).val(),
                           unit: $(elem).attr('unit')
                          };
                }
           );
}

function clickRefreshButton(widget_div) {
    widget_div.find('.refresh_button').click();
}

function setRefreshButton(widget, combis, sp_id, opts) {
    var widget_div = widget.element || widget;

    widget_div.find('.refresh_button').unbind('click').click(function(w) {
        return function () {
            var widget = w;
            var widget_div = widget.element || widget;

            var selected_service_combis = combis || _getSelectedCombinations(widget_div, 'servicecombination_list');
            var selected_node_combis    = _getSelectedCombinations(widget_div, 'nodemetriccombination_list');
            var selected_nodes          = $.map(
                                              widget_div.find('.node_list option:selected'),
                                              function(n){return {id:$(n).attr('node_id'),name:$(n).val()}}
                                          );

            // Limit the number of simultaneous series
            var total_combinations = selected_service_combis.length + (selected_node_combis.length * selected_nodes.length);
            if (total_combinations > 8) {
                alert('Too much selected combinations');
                return;
            }

            // If widget object is passed then we update its metadata and title
            if (widget.element) {
                _updateWidgetMedatada(widget,selected_service_combis,selected_node_combis,selected_nodes);
            }

            var time_settings = getPickedDate(widget_div);
            showCombinationGraph(
                    widget_div,
                    selected_service_combis,
                    selected_node_combis,
                    selected_nodes,
                    time_settings.start,
                    time_settings.end,
                    sp_id,
                    opts
            );
        }
    }(widget)).button({ icons : { primary : 'ui-icon-refresh' } }).show();
}

function _updateWidgetMedatada(widget,service_combis, node_combis, nodes) {
    // Update metadata
    widget.addMetadataValue(
            'aggregate_combination_ids',
            $.map(service_combis, function(c) {return c.id}).join(',')
    );
    widget.addMetadataValue(
            'node_combination_ids',
            $.map(node_combis, function(c) {return c.id}).join(',')
    );
    widget.addMetadataValue(
            'node_ids',
            $.map(nodes, function(n) {return n.id}).join(',')
    );

    // Update title
    var title;
    var sc_length = service_combis.length;
    var nc_length = node_combis.length;
    var n_length  = nodes.length;
    if (sc_length == 0) {
        title = nc_length == 1 ? node_combis[0].name : nc_length + ' combinations';
        title += ' for ';
        title += n_length == 1 ? nodes[0].name : n_length + ' nodes';
    } else if (nc_length == 0) {
        if (sc_length <= 2) {
            var names = $.map(service_combis, function(metric) {return metric.name});
            title =  names.join(', ');
        } else {
            title = sc_length + ' combinations';
        }
    } else {
        title = sc_length + ' service combinations, ' + nc_length + ' node combinations';
    }
    widgetUpdateTitle(widget, title);
}

// Utility function specific to used date format
// Return Unix epoch time (sec) from date/time string formatted as 'mm-dd-yy HH:MM'
function dateTimeToEpoch(dateTime) {
    return parseInt(Date.parse(dateTime.replace(/-/g, '/')) / 1000);
}

// Request data for each combinations and display them
function showCombinationGraph(curobj,service_combinations,node_combinations,nodes,start,stop, sp_id, options) {
    var widget = $(curobj).closest('.widget');
    var widget_id = $(curobj).closest('.widget').attr("id");
    var graph_container = widget.find('.clusterCombinationView');
    var model_container = widget.find('.datamodel_fields');
    graph_container.children().remove();

    var opts = options || {};

    widget_loading_start( widget );

    // Request data for each selected combination
    var error_count      = 0;
    var pending_requests = 0;

    // Service level requests
    var clustersview_url = '/monitoring/serviceprovider/' + sp_id +'/clustersview';
    pending_requests =  service_combinations.length;
    var service_data = {series:[], labels:[], units:[]};
    $.each(service_combinations, function (i, combi) {
        var params = {id:combi.id,start:start,stop:stop};
        $.getJSON(clustersview_url, params, function(data) {
            pending_requests--;
            if (data.error) {
                error_count++;
            } else {
                service_data.series.push(data.first_histovalues);
                service_data.labels.push(combi.name);
                service_data.units.push(combi.unit);
            }
        });
    });

    // Node level request
    pending_requests += node_combinations.length;
    var node_data = {series:[], labels:[], units:[]};
    var params = {
            start_time : dateTimeToEpoch(start),
            end_time   : dateTimeToEpoch(stop),
            node_ids   : $.map(nodes, function(n){return n.id})
    }
    $.each(node_combinations, function (i, combi) {
        $.post('/api/combination/'+combi.id+'/evaluateTimeSerie',
                params,
                function(data) {
                    pending_requests--;
                    $.each(nodes, function(i,n) {
                        node_data.series.push(_formatTimeSerieFromHash(data[n.id]));
                        node_data.labels.push('['+n.name+'] '+combi.name);
                        node_data.units.push(combi.unit);
                    });
                }
        ).error(function() {
            pending_requests--;
            error_count++;
        });
    });

    // Display data when all requests are done
    var graph;
    $(function displayGraph() {
        if (pending_requests == 0) {
            if (error_count == service_combinations.length + node_combinations.length) {
                graph_container.append('<br>').append($('<div>', {'class' : 'ui-state-highlight ui-corner-all', html: 'No data for selected time window'}));
                deactivateWidgetPart(widget.find('.widget_part_forcasting'), 'You must have data on the graph to forecast');
            } else {
                var div_id = 'cluster_combination_graph_' + widget_id;
                var div = $('<div>', {id:div_id});
                graph_container.css('display', 'block');
                graph_container.append(div);
                var series = service_data.series.concat(node_data.series);
                var labels = service_data.labels.concat(node_data.labels);
                var units  = service_data.units.concat(node_data.units);
                graph = timedGraph(series, start, stop, labels, units, div_id, {show_cursor : opts.allow_forecast});
                activateWidgetPart(widget.find('.widget_part_forcasting'));

                if (opts.allow_forecast) {
                    var predict_button = model_container.find('.instant_predict');
                    _pickTimeRange(graph, function() {
                        predict_button.prop('disabled', false).attr('title', '');
                    });
                    predict_button
                        .prop('disabled', true).attr('title', 'You must select training data start and end date by clicking on the graph')
                        .unbind('click')
                        .click( function() {
                            selected_model_types = $.map(model_container.find('.datamodel_type_list option:selected'),function(elem) {return $(elem).val()});
                            _autoPredict({graph:graph, combination:service_combinations[0], model_types:selected_model_types});
                        });
                }
            }
            widget_loading_stop( widget );
        } else {
            setTimeout(displayGraph, 10);
        }
    });
}

function FillModelList(widget) {
    widget.find('.refresh_models_button').unbind().click(function() {
        model_list.empty();
        model_list.append($('<option>', {text : 'Select a model', id : 'model_default'}));
        $.get('/api/combination/'+combi_id+'/data_models', function (data) {
            $(data).each( function () {
                model_list.append($('<option>', {id : this.pk, value : this.start_time + ':' + this.end_time, text : this.label}));
            });
            model_list.append($('<option>', {text : 'New model...', id : 'new_model'}));
            model_list.change();
        });
    }).click();
}

/*
 * Allow user to click on the graph to select start and end date
 * Selected range will be highlighted on the graph (using overlays)
 * Callback will be called with start and stop params
 */
function _pickTimeRange(graph, callback) {
    var selected_start_time;
    var selected_end_time;
    graph.target.bind("jqplotClick", function(ev, gridpos, datapos, neighbor) {
      if (selected_start_time === undefined || selected_end_time !== undefined) {
          selected_start_time = datapos.xaxis;
          selected_end_time = undefined;
          var start_line = {
              name      : 'start_line',
              x         : selected_start_time,
              color     : 'rgba(89, 198, 154, 0.45)',
              shadow    : false
          };
          graph.plugins.canvasOverlay.removeObject('selected_area');
          graph.plugins.canvasOverlay.addVerticalLine(start_line);
          graph.replot();
      } else {
          selected_end_time = datapos.xaxis;

          // Display selected area on graph
          var picked_area = {
              name      : 'selected_area',
              start     : [selected_start_time,0],
              stop      : [selected_end_time,0],
              lineWidth : 1000,
              lineCap   : 'butt',
              color     : 'rgba(89, 198, 154, 0.45)',
              shadow    : false
          };
          graph.plugins.canvasOverlay.removeObject('start_line');
          graph.plugins.canvasOverlay.removeObject('selected_area');
          graph.plugins.canvasOverlay.addLine(picked_area);
          graph.replot();

          // Callback
          var current_selected_start_time = parseInt(selected_start_time / 1000);
          var current_selected_end_time   = parseInt(selected_end_time / 1000);
          callback(current_selected_start_time, current_selected_end_time);

          _pickTimeRange(graph, callback);
      }
  });
}

function fillDataModelTypeList(widget_div) {
    // Available model type list
    // TODO Do not hardcode, get it from server
    var data = [
                {
                    type : 'AnalyticRegression::LinearRegression',
                    label: 'Linear regression'
                },
                {
                    type : 'AnalyticRegression::LogarithmicRegression',
                    label: 'Logarithmic regression'
                },
                {
                    type : 'RDataModel::AutoArima',
                    label: 'ARIMA'
                }
    ];

    var datamodel_type_list = widget_div.find('.datamodel_type_list');
    $(data).each( function () {
        datamodel_type_list.append($('<option>', {
            value   : this.type,
            text    : this.label,
        }).prop('selected', true));
    });
    datamodel_type_list.multiselect({
        noneSelectedText: 'Select model',
        selectedText    : "# selected models",
        selectedList    : 1,
        header : false
    });
}

/*
 * Request for auto prediction and display result on graph
 * Learning start and end time are retrieved from selected area on graph
 * Horizon is the last date visible on the graph
 */
function _autoPredict(params) {
    var graph       = params.graph;
    var combination = params.combination;
    var area  = graph.plugins.canvasOverlay.getObject('selected_area');

    var current_selected_start_time = parseInt(area.options.start[0] / 1000);
    var current_selected_end_time   = parseInt(area.options.stop[0] / 1000);
    var time_settings = getPickedDate(graph.target.closest('.widget'));

    graph.target.hide();
    elemLoadingStart(graph.target.parent(), 'Forecasting data...');
    $.ajax({
        url         : '/api/combination/'+combination.id+'/autoPredict',
        type        : 'POST',
        contentType : 'application/json',
        data        : JSON.stringify(
                {
                    model_list            : params.model_types,
                    data_start            : current_selected_start_time,
                    data_end              : current_selected_end_time,
                    predict_start_tstamps : parseInt(new Date(time_settings.start).getTime() / 1000),
                    predict_end_tstamps   : parseInt(new Date(time_settings.end).getTime() / 1000),
                }
        ),
        success     : function (prediction_data) {
            // Fill last serie (reserved for forecast) with forecast data
            graph.series[graph.data.length-1].data = _formatTimeSerieFromArrays(prediction_data);
            graph.series[graph.data.length-1].show = true;
            graph.target.show();
            graph.redraw();
            elemLoadingStop(graph.target.parent());
        },
        error       : function(error) {
            graph.target.parent().find('#predict_error_div').remove();
            graph.target.parent().prepend($('<div>', {id : 'predict_error_div', 'class' : 'ui-state-highlight ui-corner-all', html: error.responseText}));
            elemLoadingStop(graph.target.parent());
        }
    });
}


function elemLoadingStart(elem, caption) {
    var cap = caption || 'Loading...';
    elem.append(
            $('<div>', {'class' : 'loading'})
                .append($('<img>', {alt : "Loading, please wait", src : "/css/theme/loading.gif"}))
                .append($('<p>', {html : cap}))
    )
    $('*').addClass('cursor-wait');
}

function elemLoadingStop( elem ) {
    elem.find('.loading').remove();
    $('*').removeClass('cursor-wait');
}

/*
 * Transform time series format from API : {timestamps: [t1, t2], values: [v1,v2]}
 * to jqplot expected format : [[t1*1000, v1], [t2*1000, v2]]
 */
function _formatTimeSerieFromArrays(ts) {
    var formatted_ts = [];
    for (var i=0; i< ts.timestamps.length; i++) {
        // We multiply value by 1 to force number
        var value = ts.values[i] === null ? null : 1 * ts.values[i];
        formatted_ts.push([ts.timestamps[i] * 1000, value]);
    }
    return formatted_ts;
}

/*
 * Transform time series format from API : {t1 => v1, t2 => v2}
 * to jqplot expected format : [[t1*1000, v1], [t2*1000, v2]]
 */
function _formatTimeSerieFromHash(ts) {
    var formatted_ts = [];
    $.each(ts, function(timestamp, value) {
        formatted_ts.push([timestamp * 1000, value === null ? null : 1 * value]);
    });
    return formatted_ts;
}

// DEPRECATED
function dataModelManagement(e) {
    var graph_info      = e.data;
    var model_container = e.data.model_container;
    var graph_container = e.data.graph_container;
    var graph_div = $('<div>', {id: e.data.graph_div_id});

    selected_model_id = $(this).find('option:selected').attr('id');
    if (selected_model_id === 'model_default') {
        model_container.find('.forcast_config').hide();
        model_container.find('.new_model_config').hide();

        setAutoPredictControl(e.data);

        return;
    }

    graph_container.children().remove();
    graph_container.append(graph_div);
    if (selected_model_id === 'new_model') {
        timedGraph(
                [graph_info.histovalues],
                graph_info.min, graph_info.max,
                graph_info.label, graph_info.unit,
                graph_info.graph_div_id,
                []
        );
        model_container.find('.forcast_config').hide();
        model_container.find('.new_model_config').show();
        model_container.find('.learn_data').prop('disabled', true);
        pickTimeRange(e.data, [], function(start, end) {
            model_container.find('.learn_data').prop('disabled', false).unbind().click(function() {
                $.post('/api/combination/' + e.data.combi_id + '/computeDataModel', {start_time:start, end_time:end}, function() {
                    alert('Operation enqueued');
                });
            });
        });
    } else {
        model_container.find('.forcast_config').show();
        model_container.find('.new_model_config').hide();
        var selected_model_id = $(this).find('option:selected').attr('id');
        var model_time_range = $(this).find('option:selected').val().split(":");
        var overlays = [{line: {
            name      : 'pebbles',
            start     : [model_time_range[0] * 1000,0],
            stop      : [model_time_range[1] * 1000,0],
            lineWidth : 1000,
            lineCap   : 'butt',
            color     : 'rgba(89, 198, 154, 0.45)',
            shadow    : false
        }}];
        var time_settings = getPickedDate(graph_container.parent());
        var sampling_period = model_container.find('.model_sampling').val();

        // Utility function specific to used date format
        // Return Unix epoch time (sec) from date/time string formatted as 'mm-dd-yy HH:MM'
        function dateTimeToEpoch(dateTime) {
            return parseInt(Date.parse(dateTime.replace(/-/g, '/')) / 1000);
        }

        widget_loading_start( graph_info.widget );
        $.ajax({
            url         : '/api/datamodel/'+selected_model_id+'/predict',
            async       : false,
            type        : 'POST',
            contentType : 'application/json',
            data        : JSON.stringify(
                  {
                      start_time      : dateTimeToEpoch(time_settings.start),
                      end_time        : dateTimeToEpoch(time_settings.end),
                      sampling_period : sampling_period * 60,
                      data_format     :'pair',
                      time_format     :'ms'
                  }
            ),
            success     : function (prediction_data) {
                timedGraph(
                      [graph_info.histovalues, prediction_data],
                      graph_info.min, graph_info.max,
                      graph_info.label, graph_info.unit,
                      graph_info.graph_div_id,
                      overlays
                );
            },
            complete    : function () {
                widget_loading_stop( graph_info.widget );
            }
        });
    }
}

/*
 * Build jqplot parameters allowing to have multi yaxes (one for each unit)
 *
 * Create jqplot axis definition according to number of different unit in units array
 * Also build the series definition wich associate the correct axis for each serie
 */
function _buildAxisDefinition(units, xmin, xmax) {
    var axes = {
        xaxis:{
            renderer:$.jqplot.DateAxisRenderer,
            rendererOptions: {
                tickInset: 0
            },
            tickRenderer: $.jqplot.CanvasAxisTickRenderer,
            tickOptions: {
                mark        : 'inside',
                markSize    : 10,
                showGridline: false,
                angle       : -60,
                formatString: '%m-%d-%y %H:%M'
            },
            min:xmin,
            max:xmax,
        },
        yaxis:{
            label           : units[0],
            labelRenderer   : $.jqplot.CanvasAxisLabelRenderer,
            tickOptions     : {
                showMark: false,
            },
        },
    };

    var unit_yaxis = {}; unit_yaxis[units[0]] = 'yaxis';
    var yaxis_count = 1;
    var series_info = [];
    $.each(units, function(i,unit) {
        var assoc_yaxis = unit_yaxis[unit];
        if (assoc_yaxis === undefined) {
            yaxis_count++;
            var new_axis_name = 'y'+yaxis_count+'axis';
            unit_yaxis[unit] = new_axis_name;
            axes[new_axis_name] = {
                label           : unit,
                labelRenderer   : $.jqplot.CanvasAxisLabelRenderer,
                tickOptions     : {
                    showMark: false,
                    showGridline:false,
                },
                show:true,
                useSeriesColor: true,
            };
            assoc_yaxis = new_axis_name;
        }
        series_info.push({yaxis:assoc_yaxis});
    });

    return {axes:axes, series:series_info};
}

// Create graph and plot series
function timedGraph(graph_lines, min, max, labels, units, div_id, opts) {
    $.jqplot.config.enablePlugins = true;
    // var first_graph_line=[['03-14-2012 16:23', 0], ['03-14-2012 16:17', 0], ['03-14-2012 16:12', 0],['03-14-2012 16:15',null], ['03-14-2012 16:19', 0], ['03-14-2012 16:26', null]];

    var series_axes = _buildAxisDefinition(units, min, max);

    // Add empty serie that will be used for plotting forecasting data
    // TODO Find a way to dynamically add a serie on graph
    graph_lines.push([]);
    labels.push('forecast');
    series_axes.series.push({show:false, color:'rgba(200, 100, 100, 0.45)'});

    var cluster_timed_graph = $.jqplot(div_id, graph_lines, {
        seriesDefaults: {
            breakOnNull:true,
            showMarker: false,
            pointLabels: { show: false },
            yaxis  : 'yaxis',
        },
        axes    : series_axes.axes,
        series  : series_axes.series,
        legend : {
            //renderer: $.jqplot.EnhancedLegendRenderer,
            show    : true,
            location: 'nw',
            labels  : labels,
        },
        grid:{
            background: '#eeeeee',
        },
        highlighter: {
            show: true,
            // formatString: '<p class="cluster_combination_tooltip">Date: %s<br /> value: %f</p>',
        },
        canvasOverlay: {
            show    : true,
            objects : []
        },
        cursor: {
            show                : (opts && opts.show_cursor) || false,
            showVerticalLine    : true,
            clickReset          : true,
            showTooltip         : false,
        }
    });

    // Attach resize event handlers
    setGraphResizeHandlers(div_id, cluster_timed_graph);

    return cluster_timed_graph;
}

function toggleTrendLine() {
    if (cluster_timed_graph) {
        cluster_timed_graph.series[0].trendline.show = ! cluster_timed_graph.series[0].trendline.show;
        cluster_timed_graph.replot();
    }
}

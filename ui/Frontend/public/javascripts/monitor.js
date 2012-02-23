 $(document).ready(function(){
 
  	var url_params = window.location.href.split('?')[1];
  	var url = window.location.href;
	var path = url.replace(/^[^\/]+\/\/[^\/]+/g,'');	
	var content_link = path + '/graphs'; // remove the beginning of the url to keep only path
 	var save_clustermonitoring_settings_link = path + '/save';
 	var save_monitoring_settings_link = "/cgi/kanopya.cgi/monitoring/save_monitoring_settings";
    var current_path = path;


 	commonInit();
 	
 // ------------------------------------------------------------------------------------
 	
 	$('.expand_ul ul').hide();
 	$('.expand_ul').click( function() {
 		$(this).find('ul').toggle();
 	} ).addClass('clickable');

	$('[id^=X] .expandable').hide();  // hide all elems of class 'expandable' under elem with id starting with 'X'
 	$(".expander", this).click(function() {
 		
 		var elem_to_expand = $('#X'+this.id).find('.expandable');
 		
 		if ( ! $('#X'+this.id).hasClass('expand_on')) {
 			
 			$('.expanded').hide('blind', {}, 300).removeClass('expanded');
 			$('.expand_on').removeClass('expand_on');
 		}
     	elem_to_expand.toggle('blind', {}, 300);
     	elem_to_expand.toggleClass('expanded');
     	$('#X'+this.id).toggleClass('expand_on');
     	
   }).addClass('clickable');
 	
 	
 	
 	$('.select_collect').click( function () {
 				$(this).toggleClass('collected'); 
 				$(this).siblings('.select_graph').removeClass('graphed');
 	} ).addClass('clickable');
 	
 	$('.select_graph').click( function () {
 				$(this).toggleClass('graphed');
 				var id = $(this).siblings('.expander').attr('id');
 				$(this).hasClass('graphed') ? $('#X'+id+' .select_ds').addClass('on_graph') : $('#X'+id+' .select_ds').removeClass('on_graph');
 				$(this).siblings('.select_collect').addClass('collected');
 	} ).addClass('clickable');
 	
 	$('.select_ds').click( function () { $(this).toggleClass('on_graph'); } ).addClass('clickable');
 	
 	$('#save_clustermonitoring_settings').click( function () {
 			loading_start(); 
 			var set_array = $('.select_collect.collected').map( function () { return $(this).siblings('.expander').attr('id');} ).get();

 			var settings = $('.select_graph.graphed').map( function() {
 				var set_label = $(this).siblings('.expander').attr('id');
 				var graph_settings = { 'set_label': set_label };
 				$('.graph_settings_' + set_label + ' .graph_option').each( function() { 												
	 															graph_settings[$(this).attr('opt_name')] = $(this).text(); 
	 														} )
	 			graph_settings['ds_label'] = $('.graph_settings_' + set_label + ' .select_ds.on_graph').map( function() { 												
	 															return $(this).attr('id'); 
	 														} ).get().join(",");
	 														
	 			return graph_settings;
 			}).get();
 			

 			//var params = { 'collect_sets[]': set_array, 'graphs_settings': JSON.stringify(settings) };
			var params = { 'collect_sets': JSON.stringify(set_array), 'graphs_settings': JSON.stringify(settings) };
 			
 			$.get(save_clustermonitoring_settings_link, params, function(resp) {
				loading_stop();
				alert(resp);				
				
			});
 	} ).addClass('clickable');
 
 
 	$('#save_monitoring_settings').click( function () {
 		loading_start(); 
 		
 		var settings = $('pouet');
 		
 		var params = {  };
 			
		$.get(save_monitoring_settings_link, params, function(resp) {
			loading_stop();
			alert(resp);
		});
 	}).addClass('clickable');
 
 	$('.set_def_show').click( function () { $('.set_def').show(); } );
 	$('.set_def_hide').click( function () { $('.set_def').hide(); } );
 	
 	
 	$('.yes_no_choice').click( function () { $(this).text($(this).text() == 'no' ? 'yes' : 'no') } ).addClass('clickable');
 	
 	

 // ------------------------------------------------------------------------------------
 
 	$('.simpleexpand').click( function () {
 		$('#X'+this.id).toggle();
 	}).addClass('clickable');
 
 // ------------------------------------------------------------------------------------
 
 	function refreshGraph () {
 		var timestamp = new Date().getTime();
		//$(this).fadeOut('fast').attr('src',$(this).attr('src').split('?')[0] + '?' +timestamp ).fadeIn('fast');		
		$(this).attr('src',$(this).attr('src').split('?')[0] + '?' +timestamp );
 	}
 
 	setInterval( 
 		function() {
	 		$("img.autorefresh").each( refreshGraph )
 	 	} , 5000);
 
 	//$("#ivy1").show('bounce', {}, 500);
 	//$("#logo").show('slide', {}, 500);
 	//$("#logo").mouseover(function() { $(this).show('shake', {}, 500); });
 	
 	function toggleNodeSet() {
 /*
 		loading_start();
 		alert("marche pas encore... " + $(this).attr('id'));
		var anim = 'blind';//'blind/slide';
   		var anim_duration = 500;
   		$(".selected_node").removeClass('selected_node');
   		$(this).parents().find(".node_selector").addClass('selected_node');

		var set_name = $(this).attr('id');

		$(".selected_node table img").hide(anim, {}, anim_duration);

   		setTimeout( function() {
	   		var node_name = $('.selected_node').attr('id');
	   		
	   		var params;
		   	if ($('.selected_node').hasClass('expanded')) {
		   		$(".selected_node").removeClass('expanded'); 
		   		//var set_name = $('.selected_set').attr('id').split('_')[1];;
		   		params = {node: node_name, set: set_name};
		   	} else {
		   		$(".selected_node").addClass('expanded');
		   		params = {node: node_name};
		   	}
		   	
	   		// send request
	    	$.get(content_link, params, function(xml) {
				
				fill_content_container(xml);
		
				$(".selected_node img").addClass('autorefresh').show(anim, {}, anim_duration);
				loading_stop();
			});
		}, anim_duration);
*/   	 		
 	}
 
	function toggleNode() {

		loading_start();
		var anim = 'fold';//'blind/slide';
   		var anim_duration = 500;
   		$(".selected_node").removeClass('selected_node');
   		$(".activated_content_container").removeClass('activated_content_container');
   		$(this).addClass('selected_node');
   		var content_node = $("#" + $('.selected_node').attr('id') + "_content").addClass('selected_node');
   		content_node.addClass('activated_content_container');
   		
   		var delay = anim_duration;
   		//var imgs = $(".selected_node img");
   		var imgs = content_node.find("img");
   		if (imgs.size() == 0) {
   			delay = 0;
   		} else {
   			imgs.hide(anim, {}, anim_duration);
   		}

   		setTimeout( function() {
	   		var node_name = $('.selected_node').attr('id');
	   		var period = $('.selected_period').attr('id');
	   		var params;
		   	if ($('.selected_node').hasClass('expanded')) {
		   		$(".selected_node").removeClass('expanded');
		   		if ($('.selected_set').size() == 0) {
		   			$('.activated_content_container').html("");
		   			loading_stop();
		   			return;
		   		}
		   		var set_name = $('.selected_set').attr('id');
		   		params = {node: node_name, set: set_name, period: period};
		   	} else {
		   		$(".selected_node").addClass('expanded');
		   		params = {node: node_name, period: period};
		   	}
	   		// send request
	    	$.get(content_link, params, function(xml) {

				fill_content_container(xml);

				if ($('.selected_node').hasClass('expanded')) {
					$('.activated_content_container').find(".set_selector").click( toggleNodeSet ).addClass('clickable');
				}
				
				$('.activated_content_container').find("img").addClass('autorefresh').show(anim, {}, anim_duration);
				loading_stop();
			});
		}, delay);
		
	}
   
   function fill_content_container(xml) {
		$(xml).find('node').each(function(){
			var id = $(this).attr('id');
			$("#" + id + "_content").html('<table class="simplelisting"><tr><td><img src="' + $(this).attr('img_src') + '" /></td></tr></table>')
			//$("#" + id + "_content").html($(this).children());
		});
		$("#nodecount_graph img").attr('src', $(xml).find('nodecount_graph').attr('src'));
   }
   
   function loading_start() {
   		$('body').css('cursor','wait');
   		$('.set_selector').addClass('unactive_set_selector').removeClass('set_selector');
   		$('.clickable').addClass('unactive_clickable').removeClass('clickable');		
   }
   
   function loading_stop() {
   		$('body').css('cursor','auto');
   		$('.unactive_set_selector').addClass('set_selector').removeClass('unactive_set_selector');	
   		$('.unactive_clickable').addClass('clickable').removeClass('unactive_clickable');
   }
   

   $(".set_selectors .set_selector").click(function() {
   		loading_start();
   		var anim = 'fold';//'blind/slide';
   		var anim_duration = 0;
   		
   		$(".selected_set").removeClass('selected_set');
   		$(".expanded").removeClass('expanded');
   		$(this).addClass('selected_set');
   		//$("#graph_table img").hide(anim, {}, anim_duration);
   		setTimeout( function() {
   			
	   		var set_name = $('.selected_set').attr('id');
	   		var period = $('.selected_period').attr('id');
	   		// send request
	    	$.get(content_link, {set: set_name, period: period}, function(xml) {

				fill_content_container(xml);
				 
				$("#graph_table img").addClass('autorefresh');
				//$("#graph_table img").show(anim, {}, anim_duration);
				loading_stop();
			});
		}, anim_duration); 
   });


   $("#graph_table .node_selector").click( toggleNode ).addClass('clickable');
   
   //$(".period_selectors .period_selector").click(function() {
   $(".period_selector").click(function() {
   		$('.selected_period').removeClass('selected_period');
   		$(this).addClass('selected_period');
   		$('#period_label').html($(this).text());
   		var period = $(this).attr('id');
   		$('.content_container img').each( function() {
   			$(this).attr('src',$(this).attr('src').replace(/(day|hour|custom)/, period) );
   		});
   		$('#nodecount_graph img').attr('src', $('#nodecount_graph img').attr('src').replace(/(day|hour|custom)/, period) );
   		
   }).addClass('clickable');
   
   
   $('#fold_all').click( function() {
   		$('.selected_set').removeClass('selected_set');
   		$('.content_container img').hide('fold', {}, 500);
   		setTimeout( function() {$('.content_container').html('');}, 500);
   });
   
   
   //$("a").toggle(function(){ $("b").fadeOut('slow'); },function(){$("b").fadeIn('slow');});
   
   
   //$( ".draggable" ).draggable();
    // function test_ui(){
        // 0();
        // alert (current_path);
        // var s1 = 34;
        // $.getJSON(current_path, {v1: s1}, function(data) {
			// alert ('alert xml une fois pouet');
            // alert(data.values);
            // loading_stop();
        // });     
   // } 
   // $('#testcall').click (test_ui);
   timedGraph();
 });
 
var url = window.location.href;
var path = url.replace(/^[^\/]+\/\/[^\/]+/g,'');
var metric_view =path + '/metricview';


function showMetricGraph(curobj,metric){
    loading_start();
    var params = {metric: metric};
    document.getElementById('nodechart').innerHTML='';
    $.getJSON(metric_view, params, function(data) {
        document.getElementById('nodechart').style.display='block';
        barGraph(data.values, data.nodelist);
        loading_stop();
    });
}

function barGraph(values, nodelist){
    $.jqplot.config.enablePlugins = true;
    plot1 = $.jqplot('nodechart', [values], {
        animate: !$.jqplot.use_excanvas,
        seriesDefaults:{
            renderer:$.jqplot.BarRenderer,
            pointLabels: { show: true }
        },
        axes: {
            xaxis: {
                renderer: $.jqplot.CategoryAxisRenderer,
                ticks: nodelist
            }
        },
        highlighter: { show: false }
    });
 
    $('#nodechart').bind('jqplotDataClick',
        function (ev, seriesIndex, pointIndex, data) {
            $('#info1').html('series: '+seriesIndex+', point: '+pointIndex+', data: '+data);
        }
    );
}
 
 function timedGraph(){
     var line1=[['2012-08-02 4:00PM',4], ['2012-09-02 4:00PM',6.5], ['2012-10-02 4:00PM',5.7], ['2012-11-02 4:00PM',9], ['2012-12-02 4:00PM',8.2]];
      var plot1 = $.jqplot('timedClusterMetricView', [line1], {
        title:'Default Date Axis',
        axes:{
            xaxis:{
                renderer:$.jqplot.DateAxisRenderer
            }
        },
        series:[{lineWidth:4, markerOptions:{style:'square'}}]
    });
}
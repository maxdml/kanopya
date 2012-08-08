
require('jquery/jquery.form.js');

var MasterImage = (function() {

    function MasterImage(id) {
        this.id     = id;

        this.conf   = {};
        $.ajax({
            url     : '/api/masterimage/' + id,
            success : function(data) {
                this.conf   = data;
            }
        });
    }

    MasterImage.openUpload  = function() {
        var dialog  = $('<div>');
        var form    = $('<form>', { enctype : 'multipart/form-data' }).appendTo(dialog);
        $(dialog).append('<br />');
        var load    = $('<div>').progressbar({ value : 0 }).appendTo(dialog); 
        $(form).append($('<input>', { type : 'file', name : 'file',  }));
        $(form).submit(function(event) {
            $(this).ajaxSubmit({
                url             : '/uploadmasterimage',
                type            : 'POST',
                success         : function() {
                    $(dialog).dialog('close');
                },
                uploadProgress  : function(e, position, total, percent) {
                    $(load).progressbar('value', percent);
                },
            });
            return false;
        });
        $(dialog).dialog({
            title       : 'Upload a new master image',
            draggable   : false,
            resizable   : false,
            modal       : true,
            close       : function() { $(this).remove(); },
            buttons     : {
                'Ok'        : function() { $(form).submit(); },
                'Cancel'    : function() { $(this).dialog('close'); }
            }
        });
    };

    MasterImage.list        = function(cid) {
        create_grid({
            content_container_id    : cid,
            grid_id                 : 'masterimages_list',
            url                     : '/api/masterimage',
            colNames                : [ 'Id', 'Name', 'Description', 'OS', 'Size' ],
            colModel                : [
                { name : 'pk', index : 'pk', hidden : true, key : true, sorttype : 'int' },
                { name : 'masterimage_name', index : 'masterimage_name' },
                { name : 'masterimage_desc', index : 'masterimage_desc' },
                { name : 'masterimage_os', index : 'masterimage_os' },
                { name : 'masterimage_size', index : 'masterimage_size' }
            ]
        });
    };

    return MasterImage;

})();

function masterimagesMainView(cid) {
    MasterImage.list(cid);
    var addMasterImageButton    = $('<a>', { text : 'Upload a master image' }).appendTo('#' + cid);
    $(addMasterImageButton).button({ icons : { primary : 'ui-icon-arrowthickstop-1-n' } });
    $(addMasterImageButton).bind('click', MasterImage.openUpload);
}
require('KIM/component.js');

var Snmpd5 = (function(_super) {
    Snmpd5.prototype = new _super();

    function Snmpd5(id) {
        _super.call(this, id);

        this.displayed = [];
        this.relations = {};
    };

    return Snmpd5;

})(Component);

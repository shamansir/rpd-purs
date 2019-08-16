"use strict";

exports.collectPositions = function(uuids) {
    return function() {
        const vals = uuids.filter(
            function(v) { return v.type == 'node' || v.type == 'inlet' || v.type == 'outlet' }
        ).map(
            function(v) {
                const el = document.querySelector('[id="' + v.uuid + '"]');
                const elRect = el ? el.getBoundingClientRect() : { top: -1, left: -1, bottom: -1, right: -1 };
                return {
                    type : v.type,
                    uuid: v.uuid,
                    pos: { x: window.scrollX + elRect.left, y: window.scrollY + elRect.top }
                };
            }
        );
        return vals;
    };
}

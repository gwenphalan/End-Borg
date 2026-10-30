import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

// Feet/inches presentation; model values remain exact SI metres.
NumberInput {
    id: root
    property real metres: .3048
    property bool signedValue: false
    property string description: "Length"
    number: metres
    minimum: signedValue ? -1000 : .000001
    maximum: 1000
    precisionFactor: 1000000
    increment: .1524
    displayFormatter: value => formatLength(value)
    valueParser: value => parse(value)
    function formatLength(value) {
        const total = Math.abs(value) / .0254;
        let feet = Math.floor(total / 12 + 1e-9);
        let inches = Math.round((total - feet * 12) * 1000) / 1000;
        if (inches >= 12) { feet++; inches = 0; }
        return (value < 0 ? "-" : "") + feet + "' " + inches + '"';
    }
    function parse(value) {
        const raw = value.trim().replace(/′/g, "'").replace(/″/g, '"');
        const match = raw.match(/^([+-]?)\s*(?:(\d+(?:\.\d+)?)\s*(?:'|ft)\s*)?(?:(\d+(?:\.\d+)?)\s*(?:"|in))?$/i);
        if (!match || (match[2] === undefined && match[3] === undefined)) return NaN;
        return (match[1] === "-" ? -1 : 1) * (Number(match[2] || 0) * 12 + Number(match[3] || 0)) * .0254;
    }
    implicitWidth: 135
    Layout.preferredWidth: 135
    Layout.minimumWidth: 135
    Layout.maximumWidth: 135
    Layout.fillWidth: false
    Accessible.name: description + " in feet and inches; steps by six inches"
}

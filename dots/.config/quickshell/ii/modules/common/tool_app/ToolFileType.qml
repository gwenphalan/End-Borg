import QtQml

QtObject {
    property string label: "Project"
    property string extension: ".project"
    property var legacyExtensions: []
    property string mimeType: ""
    property string icon: ""
    readonly property var extensions: [extension].concat(legacyExtensions)
    readonly property var patterns: extensions.map(value => "*"+value)
    function accepts(path) {
        return extensions.some(value => path.toLowerCase().endsWith(value.toLowerCase()));
    }
    function isLegacy(path) {
        return legacyExtensions.some(value => path.toLowerCase().endsWith(value.toLowerCase()));
    }
    function suggestedName(path) {
        for(const value of legacyExtensions)
            if(path.toLowerCase().endsWith(value.toLowerCase())) return path.slice(0,-value.length)+extension;
        return path;
    }
    function normalize(path) {
        path=suggestedName(path);
        return path.toLowerCase().endsWith(extension.toLowerCase()) ? path : path+extension;
    }
}

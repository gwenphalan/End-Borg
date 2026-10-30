pragma Singleton
import QtQuick
import Quickshell

// Curated OFL fonts. Each picker control uses only its verified native axes.
// Binaries and license notices live in assets/fonts/clock.
Singleton {
    id: root
    property FontLoader googlesansflexFont: FontLoader {
        source: Qt.resolvedUrl(
                    "../../assets/fonts/clock/googlesansflex/GoogleSansFlex[ROND,opsz,slnt,wdth,wght].ttf")
    }
    property FontLoader kodemonoFont: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/clock/kodemono/KodeMono[ROND,wdth,wght].ttf")
    }
    property FontLoader frauncesFont: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/clock/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf")
    }
    property FontLoader monasansFont: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/clock/monasans/MonaSans[wdth,wght].ttf")
    }
    property FontLoader robotoserifFont: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/clock/robotoserif/RobotoSerif[GRAD,opsz,wdth,wght].ttf")
    }
    property FontLoader sciencegothicFont: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/clock/sciencegothic/ScienceGothic[CTRS,slnt,wdth,wght].ttf")
    }
    // Loading an optional face must not delay the default clock or Settings page.
    readonly property bool ready: googlesansflexFont.status === FontLoader.Ready
    function readyForFamily(family) {
        const font = ({
            "Google Sans Flex": googlesansflexFont,
            "Kode Mono": kodemonoFont,
            "Fraunces": frauncesFont,
            "Mona Sans": monasansFont,
            "Roboto Serif": robotoserifFont,
            "Science Gothic": sciencegothicFont
        })[family];
        if (font)
            return font.status === FontLoader.Ready;
        return !legacySource(family) || legacyFont.status === FontLoader.Ready;
    }
    readonly property var nativeAxes: ({
        "Google Sans Flex": ["wght", "wdth", "ROND"],
        "Kode Mono": ["wght", "wdth", "ROND"],
        "Bricolage Grotesque": ["wght", "wdth"],
        "Fraunces": ["wght", "SOFT"],
        "Mona Sans": ["wght", "wdth"],
        "Roboto Serif": ["wght", "wdth"],
        "Big Shoulders Inline": ["wght"],
        "Tourney": ["wght", "wdth"],
        "Science Gothic": ["wght", "wdth"]
    })
    function supportsAxis(family, tag) {
        const axes = nativeAxes[family] || [];
        if (tag === "roundness")
            return axes.includes("ROND") || axes.includes("SOFT");
        return axes.includes(tag);
    }
    readonly property var calibration: ({
        "Google Sans Flex": {
                "weight": 400,
                "width": 100.0,
                "weightMin": 1.0,
                "weightMax": 1000.0,
                "widthMin": 25.0,
                "widthMax": 151.0
        },
        "Kode Mono": {
                "weight": 550.0,
                "width": 100.0,
                "weightMin": 400.0,
                "weightMax": 700.0,
                "widthMin": 75.0,
                "widthMax": 125.0
        },
        "Bricolage Grotesque": {
                "weight": 400,
                "width": 87.5,
                "weightMin": 200.0,
                "weightMax": 800.0,
                "widthMin": 75.0,
                "widthMax": 100.0
        },
        "Fraunces": {
                "weight": 400,
                "width": 100,
                "weightMin": 100.0,
                "weightMax": 900.0,
                "widthMin": 100,
                "widthMax": 100
        },
        "Mona Sans": {
                "weight": 400,
                "width": 100.0,
                "weightMin": 200.0,
                "weightMax": 900.0,
                "widthMin": 75.0,
                "widthMax": 125.0
        },
        "Roboto Serif": {
                "weight": 400,
                "width": 100.0,
                "weightMin": 100.0,
                "weightMax": 900.0,
                "widthMin": 50.0,
                "widthMax": 150.0
        },
        "Big Shoulders Inline": {
                "weight": 400,
                "width": 100,
                "weightMin": 100.0,
                "weightMax": 900.0,
                "widthMin": 100,
                "widthMax": 100
        },
        "Science Gothic": {
                "weight": 400,
                "width": 100.0,
                "weightMin": 100.0,
                "weightMax": 900.0,
                "widthMin": 50.0,
                "widthMax": 200.0
        },
        "Poiret One": {
                "weight": 400,
                "width": 100,
                "weightMin": 400,
                "weightMax": 400,
                "widthMin": 100,
                "widthMax": 100
        },
        "Tourney": {
                "weight": 400,
                "width": 100.0,
                "weightMin": 100.0,
                "weightMax": 900.0,
                "widthMin": 75.0,
                "widthMax": 125.0
        }
})
    function profile(family) {
        return calibration[family] || {
            weight: 400,
            width: 100,
            weightMin: 1,
            weightMax: 1000,
            widthMin: 25,
            widthMax: 200
        };
    }
    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }
    function toControl(value, min, neutral, max) {
        return clamp(value < neutral ? (value - neutral) / Math.max(.001, neutral - min) * 100 : (value
                                                                                                  - neutral)
                                       / Math.max(.001, max - neutral) * 100, -100, 100);
    }
    function fromControl(value, min, neutral, max) {
        value = clamp(value, -100, 100);
        return neutral + value / 100 * (value < 0 ? neutral - min : max - neutral);
    }
    function controls(font) {
        return {
            weight: toControl(Number(font.weight ?? 400), 1, 400, 1000),
            width: toControl(Number(font.width ?? 100), 25, 100, 200),
            roundness: clamp(Number(font.roundness ?? 0), 0, 100),
            spacing: clamp(Number(font.letterSpacing ?? 0) * 200, 0, 100)
        };
    }
    function fromControls(values) {
        const result = {};
        if (values.weight !== undefined)
            result.weight = fromControl(values.weight, 1, 400, 1000);
        if (values.width !== undefined)
            result.width = fromControl(values.width, 25, 100, 200);
        if (values.roundness !== undefined)
            result.roundness = clamp(values.roundness, 0, 100);
        if (values.spacing !== undefined)
            result.letterSpacing = clamp(values.spacing, 0, 100) / 200;
        return result;
    }

    // Legacy saved families are loaded only when they are actually displayed.
    readonly property var legacyFiles: ({
                                            "Merriweather":
                                            "../../assets/fonts/clock/merriweather/Merriweather[opsz,wdth,wght].ttf",
                                            "Anybody":
                                            "../../assets/fonts/clock/anybody/Anybody[wdth,wght].ttf",
                                            "Inconsolata":
                                            "../../assets/fonts/clock/inconsolata/Inconsolata[wdth,wght].ttf",
                                            "Archivo":
                                            "../../assets/fonts/clock/archivo/Archivo[wdth,wght].ttf",
                                            "Nupuram":
                                            "../../assets/fonts/clock/nupuram/Nupuram.ttf",
                                            "Playfair":
                                            "../../assets/fonts/clock/playfair/PlayfairRomanVF.ttf",
                                            "Bungee Inline":
                                            "../../assets/fonts/clock/bungeeinline/BungeeInline-Regular.ttf",
                                            "Poiret One":
                                            "../../assets/fonts/clock/poiretone/PoiretOne-Regular.ttf",
                                            "Bricolage Grotesque":
                                            "../../assets/fonts/clock/bricolagegrotesque/BricolageGrotesque[opsz,wdth,wght].ttf",
                                            "Big Shoulders Inline":
                                            "../../assets/fonts/clock/bigshouldersinline/BigShouldersInline[opsz,wght].ttf",
                                            "Tourney":
                                            "../../assets/fonts/clock/tourney/Tourney[wdth,wght].ttf",
                                            "Press Start 2P":
                                            "../../assets/fonts/clock/pressstart2p/PressStart2P[BLED,JITT,ROND,wdth,wght].ttf",
                                            "Tiny5":
                                            "../../assets/fonts/clock/tiny5/Tiny5[BLED,JITT,ROND,wdth,wght].ttf",
                                            "Tiny5 Mono":
                                            "../../assets/fonts/clock/tiny5mono/Tiny5Mono[BLED,JITT,ROND,wdth,wght].ttf",
                                            "Tiny5 Duo":
                                            "../../assets/fonts/clock/tiny5duo/Tiny5Duo[BLED,JITT,ROND,wdth,wght].ttf"
                                        })
    function legacySource(family) {
        return legacyFiles[family] ? Qt.resolvedUrl(legacyFiles[family]) : "";
    }
    property FontLoader legacyFont: FontLoader {}
    function ensureLegacyFamily(family) {
        const source = legacySource(family);
        if (source && legacyFont.source.toString() !== source.toString())
            legacyFont.source = source;
    }
    function choiceId(choice) {
        return choice.family + (choice.italic ? " Italic" : "");
    }
    function matches(choice, font) {
        return choice.family === font.family && !!choice.italic === !!font.italic;
    }
    readonly property var choices: [
        { "name": "Round", "family": "Google Sans Flex", "italic": false },
        { "name": "Mono", "family": "Kode Mono", "italic": false },
        { "name": "Soft serif", "family": "Fraunces", "italic": false },
        { "name": "Geometric", "family": "Mona Sans", "italic": false },
        { "name": "Serif", "family": "Roboto Serif", "italic": false },
        { "name": "Display", "family": "Science Gothic", "italic": false }
    ]
}

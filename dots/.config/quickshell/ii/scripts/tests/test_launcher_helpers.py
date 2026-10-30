import pathlib
import re
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class LauncherTests(unittest.TestCase):
    def run_js(self, source, assertions):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js is required for QML JavaScript helper tests")
        subprocess.run(
            [node, "-e", 'const assert = require("node:assert/strict");\n'
             + source + "\n" + assertions],
            check=True, capture_output=True, text=True,
        )

    def test_labels_preserve_identity_and_unknown_names(self):
        source = (ROOT / "modules/ii/overview/LauncherLabels.js").read_text()
        self.run_js(source.replace(".pragma library", ""), """
const app = {id: "cmake-gui.desktop", name: "CMake GUI"};
assert.equal(displayName(app, [app]), "CMake");
assert.equal(displayName(app, [app, {id: "other", name: "CMake"}]), "CMake GUI");
const unknown = {id: "unknown", name: "An unfamiliar long application name"};
assert.equal(displayName(unknown, [unknown]), unknown.name);
assert.equal(displayName({id: "blueman-manager", name: "Bluetooth Manager"}, []),
             "Bluetooth Manager");
""")

    def test_mode_prefix_changes_preserve_query(self):
        source = (ROOT / "services/LauncherSearch.qml").read_text()
        function = re.search(r"    function ensurePrefix\(prefix\) \{.*?\n    \}", source, re.S)
        self.assertIsNotNone(function)
        self.run_js("""
const Config = {options: {search: {prefix: {
    action: ">", app: "/", clipboard: ";", emojis: ":", math: "=",
    shellCommand: "$", webSearch: "?"
}}}};
const root = {query: "hello"};
""" + function.group(), """
ensurePrefix(";"); assert.equal(root.query, ";hello");
ensurePrefix(";"); assert.equal(root.query, ";hello");
ensurePrefix(":"); assert.equal(root.query, ":hello");
root.query = ""; ensurePrefix(";"); assert.equal(root.query, ";");
""")

    def test_clipboard_writes_only_after_start(self):
        source = (ROOT / "services/Cliphist.qml").read_text()
        for process in ("copyProc", "deleteProc"):
            block = source.split("id: " + process, 1)[1].split("\n    Process {", 1)[0]
            self.assertIn("onStarted:", block)
            self.assertNotIn("onRunningChanged:", block)
            self.assertIn('write(currentEntry + "\\n")', block)

    def test_directional_motion_uses_behavior_target(self):
        motions = {
            "SpotlightController.qml": ("presence", "barReveal"),
            "SpotlightRevealMotion.qml": ("widthProgress", "heightProgress", "travelProgress"),
            "SpotlightContentMotion.qml": ("progress",),
        }
        for filename, properties in motions.items():
            source = (ROOT / "modules/ii/overview" / filename).read_text()
            for prop in properties:
                with self.subTest(file=filename, property=prop):
                    behavior = re.search(
                        rf"    Behavior on {prop} \{{.*?\n    \}}", source, re.S
                    )
                    self.assertIsNotNone(behavior)
                    block = behavior.group()
                    self.assertGreaterEqual(block.count(".targetValue === 1"), 2)
                    self.assertNotRegex(block, r"root\.(shown|searchShown|barExpanded)\s*\?")

    def test_overview_content_motion_is_separate_from_capture(self):
        overview = (ROOT / "modules/ii/overview/Overview.qml").read_text()
        widget = (ROOT / "modules/ii/overview/OverviewWidget.qml").read_text()
        wrapper = (ROOT / "modules/ii/overview/SpotlightOverviewView.qml").read_text()
        self.assertIn("captureEnabled: lowerSurface.visible && overviewLoader.visible", overview)
        self.assertIn("contentShown: lowerSurface.shown && viewHost.overviewActive", overview)
        self.assertIn("contentShown: root.contentShown", wrapper)
        self.assertIn("shown: root.contentShown", widget)
        self.assertNotIn("shown: root.captureEnabled", widget)

    def test_only_apps_have_section_navigation(self):
        results = (ROOT / "modules/ii/overview/SpotlightResults.qml").read_text()
        apps = (ROOT / "modules/ii/overview/SpotlightPanel.qml").read_text()
        self.assertNotIn("SpotlightSectionRail", results)
        self.assertNotIn("left: rail.right", results)
        self.assertIn("SpotlightSectionRail", apps)

    def test_lower_views_share_one_morphing_material_surface(self):
        overview = (ROOT / "modules/ii/overview/Overview.qml").read_text()
        surface = (ROOT / "modules/ii/overview/SpotlightSurface.qml").read_text()
        widget = (ROOT / "modules/ii/overview/OverviewWidget.qml").read_text()
        search = (ROOT / "modules/ii/overview/SpotlightSearchBar.qml").read_text()
        self.assertEqual(overview.count("SpotlightSurface {"), 1)
        self.assertNotIn("id: overviewSurface", overview)
        self.assertNotIn("SpotlightMaterial {", widget)
        self.assertIn("shown: state.open && state.panelsReady\n", overview)
        self.assertIn("Behavior on layoutWidth", surface)
        self.assertIn("Behavior on layoutHeight", surface)
        self.assertIn("surfaceColor: Appearance.colors.colBackgroundSurfaceContainer", overview)
        self.assertIn("baseColor: Appearance.colors.colBackgroundSurfaceContainer", search)
        self.assertNotIn("scale:", surface)

    def test_scrollbars_hide_when_idle_and_have_inset_tracks(self):
        scrollbar = (ROOT / "modules/ii/overview/SpotlightScrollBar.qml").read_text()
        self.assertIn("readonly property bool interacting: pressed || hovered || active || scrolling", scrollbar)
        self.assertIn("if (interacting) linger.stop();", scrollbar)
        self.assertIn("else linger.restart();", scrollbar)
        self.assertIn("root.interacting || linger.running ? 0.5 : 0", scrollbar)
        for name in ("SpotlightPanel.qml", "SpotlightResults.qml"):
            source = (ROOT / "modules/ii/overview" / name).read_text()
            self.assertIn("topMargin: 16; bottomMargin: 16", source)
            self.assertIn("scrolling: scrollMotion.running || sidebarScrollAnimation.running || list.moving", source)

    def test_search_placeholder_is_the_same_in_every_mode(self):
        search = (ROOT / "modules/ii/overview/SpotlightSearchBar.qml").read_text()
        self.assertIn('placeholderText: Translation.tr("Search...")', search)
        self.assertNotIn('Translation.tr("Search, calculate or run")', search)
        self.assertNotIn('Translation.tr("Search clipboard")', search)

    def test_results_do_not_stack_excessive_right_padding(self):
        results = (ROOT / "modules/ii/overview/SpotlightResults.qml").read_text()
        item = (ROOT / "modules/ii/overview/SearchItem.qml").read_text()
        self.assertNotIn("rightMargin: 24", results)
        self.assertIn("rightContentMargin: 8", results)
        self.assertIn("anchors.rightMargin: root.rightContentMargin", item)

    def test_apps_navigation_keeps_only_populated_letters_visible(self):
        rail = (ROOT / "modules/ii/overview/SpotlightSectionRail.qml").read_text()
        self.assertRegex(rail, r"readonly property var visibleEntries: sections\s*\n")
        panel = (ROOT / "modules/ii/overview/SpotlightPanel.qml").read_text()
        positions = panel.split("readonly property var sectionPositions: {", 1)[1]
        positions = positions.split("\n    }\n", 1)[0]
        self.run_js("""
const controller = {hiddenExpanded: false};
const Logic = {letter: name => name[0].toUpperCase()};
const rows = [
    {kind: "header", section: "pinned", title: "Pinned", height: 42},
    {kind: "apps", apps: [{name: "Ghost"}], height: 110},
    {kind: "header", section: "apps", title: "All Apps", height: 42},
    {kind: "apps", section: "apps", apps: [{name: "Alpha"}, {name: "Atom"}], height: 110},
    {kind: "apps", section: "apps", apps: [{name: "Beta"}, {name: "Zulu"}], height: 110},
    {kind: "apps", hidden: true, apps: [{name: "Gamma"}], height: 110}
];
const rowHeight = row => row.hidden ? 0 : row.height;
const positions = (() => {
""" + positions + """
})();
""", """
assert.deepEqual(positions.filter(entry => entry.letter).map(entry => entry.letter),
                 ["A", "B", "Z"]);
assert.equal(positions.filter(entry => entry.letter === "A").length, 1);
assert.equal(positions.find(entry => entry.letter === "B").y, 304);
""")


if __name__ == "__main__":
    unittest.main()

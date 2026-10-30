# Lens Cap

Launch **Lens Cap** from the desktop launcher, or run
`~/.local/bin/lens-calibration [project.lenscap]`.
The app entry point is `../../lensCalibration.qml`; it shares Settings'
AppWindow, Appearance, buttons, compact inputs and SaveChangesDialog.
The desktop shell and settings schema are unchanged. A horizontal Settings-style
bar holds file/calibration/export actions; two floating pills hold canvas tools.

## Current scope

Lens Cap contains **Lens correction** and **Reference plane** only. Polygon and
region drawing is handled by the **LabelMe** top-bar action on the corrected
image. Built-in 2D/3D region editors and Blender-region import are no longer
exposed. Existing project annotations and 3D data remain preserved for compatibility.
Blender camera/reference export and recalibration remain available.

## Workflow

1. Startup shows the canvas with a modal aperture-logo dialog containing
   **New image** and **Open project**. Choosing either dismisses that dialog before
   opening the picker; cancelling returns to the startup dialog. New image opens the GNOME Files (Nautilus)
   chooser directly; desktop-wide file manager/portal settings are untouched.
2. Trace at least three architectural edges with three or more distinct points each. Longer edges provide stronger constraints.
   Place points on the actual edge, including its curved middle. Spread traces
   around the image, away from the center. Enter/right-click finishes a trace.
3. **Settings** opens a centered project settings dialog using the actual grouped Settings rows, headers, icons and
   controls. Set optional custom horizontal FOV, radial model and pixel snapping;
   Apply saves these to the project. **Calculate** applies settings and calibrates. Default is k1. Use k1+k2 only with five or more
   independent traces. RMS measures point-to-best-fit-line distance in pixels.
4. Compare Original/Corrected. **Settings → Adjust coefficients** permits
   manual refinement; manual values do not retain the fitted RMS score.
5. Optional: **Settings → Save preset** stores this camera correction without
   traces or annotations. On a different reference image use **Load preset**.
   Image dimensions must match; use the same camera/crop/orientation.
6. Optional: **Settings → Add extra images** selects additional snapshots.
   Only the original reference image supplies calibration traces. All added images
   receive that exact correction and must match its source dimensions.
7. Click **LabelMe**. The corrected reference and extra images are written into
   a managed temporary folder and the active PNG opens in LabelMe with its neighboring images available. Draw and save
   polygons, then close LabelMe. Every saved JSON is mapped back automatically.
   Lens Cap hides while LabelMe is open and returns when it closes.
   No manual image export or JSON import is needed for this handoff.
   **File → Normalize region vertices…** merges close vertices across different
   regions, including intersections created by cropping at the curved image edge.
   Smooth boundary samples are preserved. **File → Snap vertices to edges…** is
   a separate operation. Normalization uses original/corrected image pixels to
   match the active view; edge snapping uses corrected-image pixels. Both skip
   unsafe moves while keeping safe changes.
8. **Export → Distorted LabelMe JSON** maps annotations back onto the original
   distorted image, preserving repeated labels, flags, group IDs and descriptions.
   It writes ordinary LabelMe pixel coordinates and references the original image.
   Select an existing JSON destination when updating that annotation file.
   **Export → Frigate zones** saves normalized polygons as JSON (also valid YAML).
   Single-image export contains `zones`; a batch contains `images`, each with
   its source path and its own `zones` snippet. The app does not deploy Frigate.
9. **Save** preserves reference traces/calibration, extra-image paths and hashes,
   and every imported region in a `.lenscap` JSON document. **Save** updates
   that file; **Save as** chooses a new path. Reopen with **Open project**. Keep the originals at
   their saved locations. Save the project or export regions before closing.

LabelMe working images and JSON live under the worker's temporary directory
(`/tmp/lens-calibration-…/annotations-…/`). They are reused for the same image set
and correction while the app runs, and removed on normal shutdown. Projects record
the temporary directory and embed saved LabelMe annotations; reopening regenerates
working images and annotations if the temporary files are gone. No persistent
asset folders accumulate in app storage. Original
files are never overwritten. Changing the reference correction invalidates mapped
regions; the app blocks changing it while its LabelMe instance is open.

Manual **Export → Corrected PNG** and **File → Import LabelMe** remain available
for annotating elsewhere. Use the exact exported image without resizing/cropping.

## Canvas

- Upper floating pill: New curve and Edit curve. New creates independent curves;
  click points and finish with Enter or right-click. Finishing
  deselects the curve and its point.
- Edit selects curves/points, drags points, edits x/y coordinates and deletes.
  Select the first endpoint then click empty image space to prepend, or select
  the last endpoint to append. Alt-click a straight segment to insert a point
  between its neighbours. Edit never creates an independent curve.
- Edit shows actual nodes connected by straight segments. Outside Edit, finished
  curves hide nodes and use a cubic Bézier display path with up to one pixel of
  local noise smoothing. Endpoints and saved annotations are preserved. The
  calibration uses the original placed nodes, not the smoothed display.
- Lower floating pill: undo and redo. Context actions are at the canvas top right.
  Zoom/reset are at the footer left; reset stays visible and disabled at standard fit. Cursor pixel
  coordinates are shown in the footer.
- D: New curve. V: Edit. F: reset view. Tab: original/corrected.
- Wheel: zoom around cursor. Middle drag or Ctrl+drag on empty canvas: pan.
- In New curve, Alt bypasses whole-pixel snapping. In Edit, arrow keys move a
  selected point by 0.1 px; Shift+arrows by 1 px. Delete removes a point;
  Shift+Delete removes its curve. Escape clears the selection.
- Ctrl+Z / Ctrl+Shift+Z: undo/redo. Undo while creating a curve keeps the remaining
  curve active. Ctrl+O / Ctrl+S: open project/save. Ctrl+Shift+S: save as.
- Editing traces invalidates calibration and imported polygons. Recalculate and
  reimport so exports correspond to the current mapping.

## Geometry and validation

`geometry.py` owns transforms and optimization; `backend.py` owns disk I/O and
the JSON worker protocol; QML owns viewport and annotations. The worker is a
separate persistent process, so calibration and remapping do not block Qt.

The Brown radial model maps corrected pixels to original pixels. The default K
uses f=max(width,height), principal point=((width-1)/2,(height-1)/2). With a custom
horizontal field of view, f=width/(2 tan(HFOV/2)); HFOV is stored with the calibration,
project and preset and used throughout correction and polygon mapping. No Tapo
intrinsic values are assumed. Changing HFOV invalidates the previous correction
and mapped polygons while preserving the traced curves.
The entire source perimeter is corrected and its bounds define an expanded
output canvas at the original pixel scale. Nothing is cropped or scaled down.
The output K translates the principal point by the recorded output origin;
preview, overlays, LabelMe and inverse mapping all use that geometry. The source
dimensions stay unchanged for Frigate normalization. All sparse calculations use
float64 and checked Newton inversion. There is no EXIF rotation.

The solver minimizes robust orthogonal distance of corrected **trace points**
to their independently fitted lines. Display splines are only drawing aids;
interpolated spline points are not treated as additional measurements. Short,
central, rank-deficient, folded, boundary-limited or badly fitting solutions
are rejected. Radial-only correction assumes the optical center is near the
image center. A real C101 snapshot and carefully placed traces remain necessary
for checking camera-specific quality; this is not a full intrinsic calibration.

Closed LabelMe edges are sampled at most every 2 corrected-image pixels before
the inverse mapping. Normalization divides original x/y by original width/height
(as used by Frigate). Black margins remain where the curved image does not fill the rectangular
canvas. After inverse mapping, polygon geometry is intersected with the original
image rectangle. Overshooting portions are cropped automatically; fully outside
regions are omitted. Concave regions that split are exported as separate labeled
parts. Clipping preserves boundary intersections rather than clamping vertices.
Use an identically framed stream; changing crop/orientation requires recalibration.

## Dependencies and tests

Installed isolated runtime: `~/.local/share/lens-calibration/venv`.
To recreate: `uv venv ~/.local/share/lens-calibration/venv`, then
`uv pip install --python ~/.local/share/lens-calibration/venv/bin/python -r requirements.txt`.
Tests also require pytest. Run from this directory:

```
~/.local/share/lens-calibration/venv/bin/python -m pytest -q
```

Tests cover known/noisy fits, weak constraints, invertibility, subpixel round
trips, OpenCV raster agreement, densification, normalization, session identity,
source preservation, and exports. Live smoke testing used a synthetic barrel
image with k1=-0.32; the QML worker recovered -0.32000000000000517 and reduced
line RMS from 5.2215 px to below 1e-12 px. This does not establish real-camera
accuracy. The IPC target `lensCalibration` exposes state, openSession, calculate
and toggleView for repeatable integration checks; opening refuses dirty state.

## Integration verification

`../../lensCalibrationTest.qml` runs QtTest against the real workspace and worker
in an independent Quickshell window. It needs the Wayland desktop (shared shell
singletons require a real PanelWindow backend). Its `LENS TOTAL` log must report
zero failures; Quickshell's process exit code alone does not report QtTest failures.
Synthetic fixtures can be regenerated with `prepare_test_fixtures.py` in this
folder. Run from the Quickshell root:

```
~/.local/share/lens-calibration/venv/bin/python scripts/lens_calibration/prepare_test_fixtures.py
qs -p lensCalibrationTest.qml --no-color
```

The native Files chooser helper uses the installed system Python/Gio and
Nautilus' FileChooser interface. The Qt fallback picker has been removed.

The Hyprland rule in `~/.config/hypr/custom/rules.lua` matches only Nautilus
windows titled `Lens Cap - Open` or `Lens Cap - Save`, and opens
them floating and centered at 60% monitor width / 70% height. Ordinary Files
windows retain their existing behavior.

The expanded workflow harness accepts `QS_LENS_TEST_FIXTURE` (folder containing
`session.json` and `labelme.json`) and `QS_LENS_TEST_ORDER` (1 or 2), so the same
UI suite can be run on an actual camera image. It covers fifteen workflow tests, including project settings/HFOV, viewport retention,
project Save/Save As, window hide/restore,
presets and two-image LabelMe folders.
`qs -p lensStartupTest.qml --no-color` tests the real main-window startup state
transitions using the actual-image fixture under `/tmp/lens-real-verification`.

Full-coverage framing is always used. With the actual test calibration, the
1920×1080 source expands to 2206×1242. Saved projects/presets record the source K,
output origin, expanded dimensions and output K. Older version-1 session polygons
are translated into the expanded frame without changing original coordinates.

File history is metadata only: `$XDG_STATE_HOME/lens-calibration/recent.json`
(default `~/.local/state/lens-calibration/recent.json`). File → Recent projects
lists existing projects in most-recent-first order. Files remembers separate last
folders for projects, source images, presets, LabelMe imports and each export type.
Cancelled choices do not update history, and missing folders fall back to the
current project/source directory. Generated images still live only in temporary storage.

Lens Cap saves new projects as `.lenscap`; opening a legacy `.lensproject` first asks **Convert file?**, with the conversion explained in its body.
Conversion renames the validated file without changing its JSON or overwriting an existing target.
Both file types are associated with Lens Cap and use its aperture icon.

Shared chrome, document workflows and picker transport live in `modules/common/tool_app/`.
Read its `README.md` and `AGENTS.md` before changing application chrome. Generic Python
file/history/picker/registration helpers live in `scripts/tool_app/`; Lens-specific
calibration, mapping, settings schema and canvas interaction stay in this application.

The root `lensCalibration.qml` is a standalone lazy entry for
`apps/lensCap/LensCapWindow.qml`. It disables file-triggered QML engine reloads
only for Lens Cap; the desktop shell stays independent. Reopen Lens Cap to load
QML code updates. Both Draw Regions and Export remain visibly greyed out until
a correction is available.

Drawing-only geometry checks: `node scripts/lens_calibration/test_curve_geometry.mjs`.

Lens Profile in Settings selects a named reusable correction or None. Save Profile opens
a naming modal; Rename, Update, and Delete sit to the dropdown’s right and disable
without a selection. Named profile JSON files live beside application history under
`$XDG_STATE_HOME/lens-calibration/profiles` (normally `~/.local/state/lens-calibration/profiles`).
These small calibration files persist; generated corrected images remain temporary.
Profile names are unique, updates retain the name, and deletion removes the profile file.

Shift-click selects every point on a curve. Ctrl-click toggles individual points,
including points from other curves, without selecting intervening points. Dragging,
nudging, and x/y edits operate on the selected set; multi-selection x/y fields
show its centroid. Group movement clamps as a unit to preserve relative spacing.
The footer uses shared cheatsheet keycaps in one inline row before the right-hand
point inputs. Image dimensions/status text were removed. Errors and operation updates
use an in-window toast; successful project saves only clear the reserved asterisk
on Save, without changing its width. No Finish Curve button is shown.

Window-free selection checks: `node scripts/lens_calibration/test_selection_headless.mjs`.

M connects exactly two selected endpoints from different curves, reversing their point
order as needed. Joining is one undoable edit and coincident endpoints are deduplicated.
Mouse hints use actual left/right mouse symbols; keyboard shortcuts use cheatsheet keycaps.
The fixed-width Save button reads Save* while dirty and Save after a successful save.

Calibration has no per-trace percentage-length cutoff. All traces with at least
three distinct points contribute to the joint robust fit; incomplete/two-point
traces are skipped and counted in the calibration result. Global spatial coverage,
conditioning, residual quality, and invertibility checks remain enforced.

Calibration fits are constrained to a monotone radial mapping across the entire
source footprint, including the corrected corner radius, rather than fitting an
unconstrained model and rejecting it afterward. A minimum radial derivative of
0.15 is an application conditioning policy; exact endpoint/interior extrema are
also checked. The robust `soft_l1` loss reduces small point-placement errors.

A limited or systematically curved k1 fit can recommend k1+k2 only after a stable valid fit
substantially improves residuals; with six or more traces it must also improve
whole-trace held-out checks. The toast offers an explicit model-change action;
a manually chosen model is never silently replaced. This is evidence from the traced
edges, not independent ground-truth camera calibration.

Worker errors preserve a code and original zero-based trace diagnostics. Invalid
traces and independently isolated conflicts receive canvas markers and specific
messages. Global model/coverage failures do not arbitrarily mark good traces.
Failed fits or preview writes preserve the previous usable calibration/regions.

Primary references: [OpenCV camera calibration](https://docs.opencv.org/4.x/d9/d0c/group__calib3d.html),
[stable polynomial calibration](https://arxiv.org/html/1409.5753v1),
[plumb-line calibration](https://www.ipol.im/pub/art/2011/ags-alde/) and
[SciPy robust optimization](https://docs.scipy.org/doc/scipy/reference/generated/scipy.optimize.least_squares.html).
`fixtures/bed_vision_traces.json` contains numerical traces only for the real
11-trace regression; no source photograph or user filesystem paths are included.

Radial model defaults to Auto (`projectSettings.order: 0`). It starts with k1
and chooses k1+k2 only when the stable constrained comparison meets the existing
meaningful-improvement and whole-trace validation checks. Stored calibration
`order` remains the actual fitted order (1 or 2); `modelSelection: "auto"` and
`selectionReason` record why it was selected. Project/profile settings retain
Auto independently of that numerical result. Existing explicit k1/k1+k2 project
settings remain manual overrides. No extra coefficients are selected merely
because they improve training error slightly.

### Blender scene export

After saving a reference plane and calculating 3D, use **Export to Blender** in
Reference plane operations, or **Export → Blender scene**. Blender must be installed;
export runs it in the background without opening another window. The `.blend` packs
the corrected reference image and calibrated distortion map, so no asset directory
is required beside the export. Existing authored 3D objects are included.

The camera uses the solved pose and corrected-image intrinsics, and the measured
reference mesh uses the project's dimensions and signed axis assignments. Coordinates
remain metres internally. The reference mesh is a wire guide, excluded from renders.
The corrected image appears as a camera background and in the render compositor.
The compositor applies the calibrated Brown radial distortion to return the render
to the original camera's image framing. Blender's ordinary viewport remains a
pinhole view; view the composited render to see distortion. Export reproduces the
calibration model, whose accuracy still depends on lens fitting and reference corners.

The file opens in **Calibrated camera - distorted sensor output**, where F12
produces the original sensor-sized image. Switch to **Calibrated camera -
undistorted workspace** for accurately aligned viewport editing. Both scenes
share their objects; edits carry through to the distorted output. The output
scene's viewport is a helper view, not the distortion-correct camera preview.
An embedded **Lens Cap - Read me** text block includes these instructions.

### Recalibrate an existing Blender file

Use **Recalibrate Blender file** in Reference plane operations, or **File →
Recalibrate Blender**, after calculating the current reference plane. Choose the
existing `.blend`, then save a separate `<name>-recalibrated.blend` copy.
The calibrated camera, reference guide, packed background and distortion pipeline
are rebuilt from the current project. Authored meshes (including non-box objects),
transforms, materials, collections, lights, and unrelated scenes are preserved;
this is distinct from importing only boxes into Lens Cap. The existing file is
read with embedded scripts disabled and is never overwritten by this flow.

Stale 3D calibration and stale 2D region mappings have separate feedback. A
current reference-plane solve does not trigger a stale-plane warning merely
because 2D regions were drawn under an older lens correction.

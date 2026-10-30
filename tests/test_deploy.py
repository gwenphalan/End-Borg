import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("end_borg_deploy", Path(__file__).resolve().parents[1] / "tools/deploy.py")
deploy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deploy)


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.target = self.root / "source", self.root / "target"
        self.baseline = self.root / "baseline.json"
        self.report, self.backup = self.root / "validation.json", self.root / "backup"
        self.put(self.target, "hypr/custom/rules.lua", "before", 0o640)
        self.put(self.source, "hypr/custom/rules.lua", "after", 0o600)
        deploy.snapshot(self.target, self.baseline)

    def put(self, root, relative, content, mode=0o644):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(mode)
        return path

    def validate(self, runtime=True):
        planned = deploy.plan(self.source, self.target, self.baseline)
        self.report.write_text(json.dumps({"passed": True, "runtime_validated": runtime,
                                          "source_manifest_sha256": planned["source_manifest_sha256"]}))
        return planned

    def apply(self):
        return deploy.apply(self.source, self.target, self.baseline, self.report, self.backup)

    def test_plan_is_read_only_and_preserves_unmanaged_generated_and_extra_files(self):
        extra = self.put(self.target, "hypr/extra.lua", "keep")
        generated = self.put(self.target, "hypr/hyprlock.conf", "private generated")
        self.put(self.source, "hypr/hyprlock.conf", "never deploy")
        self.put(self.source, "illogical-impulse/config.json", "private settings")
        self.put(self.source, "hypr/rules.lua.bak-before", "backup")
        planned = deploy.plan(self.source, self.target, self.baseline)
        self.assertEqual([change["path"] for change in planned["changes"]], ["hypr/custom/rules.lua"])
        self.assertEqual((self.target / "hypr/custom/rules.lua").read_text(), "before")
        self.assertEqual(extra.read_text(), "keep")
        self.assertEqual(generated.read_text(), "private generated")

    def test_apply_and_rollback_restore_content_mode_links_and_remove_new_files(self):
        self.put(self.source, "quickshell/ii/new.qml", "new")
        link = self.source / "quickshell/ii/link.qml"
        link.symlink_to("new.qml")
        self.validate()
        self.apply()
        changed = self.target / "hypr/custom/rules.lua"
        self.assertEqual(changed.read_text(), "after")
        self.assertEqual(changed.stat().st_mode & 0o777, 0o600)
        self.assertEqual(os.readlink(self.target / "quickshell/ii/link.qml"), "new.qml")
        proposed = deploy.rollback(self.backup)
        self.assertFalse(proposed["applied"])
        self.assertEqual(changed.read_text(), "after")
        deploy.rollback(self.backup, True)
        self.assertEqual(changed.read_text(), "before")
        self.assertEqual(changed.stat().st_mode & 0o777, 0o640)
        self.assertFalse((self.target / "quickshell/ii/new.qml").exists())
        self.assertFalse((self.target / "quickshell/ii/link.qml").is_symlink())
        self.assertEqual(deploy.rollback(self.backup)["rollback_changes"], [])

    def test_drift_blocks_all_writes(self):
        self.validate()
        changed = self.put(self.target, "hypr/custom/rules.lua", "edited while staging")
        self.assertEqual(deploy.plan(self.source, self.target, self.baseline)["drift"], ["hypr/custom/rules.lua"])
        with self.assertRaisesRegex(ValueError, "Live drift"):
            self.apply()
        self.assertEqual(changed.read_text(), "edited while staging")
        self.assertFalse(self.backup.exists())

    def test_mode_only_drift_blocks_apply(self):
        self.validate()
        (self.target / "hypr/custom/rules.lua").chmod(0o644)
        with self.assertRaisesRegex(ValueError, "Live drift"):
            self.apply()

    def test_stale_or_missing_runtime_validation_blocks_apply(self):
        self.validate(runtime=False)
        with self.assertRaisesRegex(ValueError, "Validation"):
            self.apply()
        self.validate()
        self.put(self.source, "hypr/custom/rules.lua", "new staged change")
        with self.assertRaisesRegex(ValueError, "Validation"):
            self.apply()

    def test_explicit_partial_runtime_deployment_keeps_truthful_journal(self):
        plan = self.validate(runtime=False)
        self.report.write_text(json.dumps({"passed": False, "runtime_validated": False,
                                          "static_passed": True, "runtime_smoke_passed": True,
                                          "source_manifest_sha256": plan["source_manifest_sha256"]}))
        with self.assertRaisesRegex(ValueError, "Validation"):
            self.apply()
        result = deploy.apply(self.source, self.target, self.baseline, self.report, self.backup,
                              allow_partial_runtime=True)
        self.assertEqual(result["validation"], {"runtime_validated": False,
                                              "partial_runtime_authorized": True})
        deploy.rollback(self.backup, True)
        self.assertEqual((self.target / "hypr/custom/rules.lua").read_text(), "before")

    def test_partial_runtime_authorization_does_not_bypass_checks_or_drift(self):
        plan = self.validate(runtime=False)
        report = {"passed": False, "runtime_validated": False,
                  "static_passed": True, "runtime_smoke_passed": True,
                  "source_manifest_sha256": plan["source_manifest_sha256"]}
        for missing in ["static_passed", "runtime_smoke_passed", "source_manifest_sha256"]:
            self.report.write_text(json.dumps({k: v for k, v in report.items() if k != missing}))
            with self.assertRaisesRegex(ValueError, "Validation"):
                deploy.apply(self.source, self.target, self.baseline, self.report, self.backup,
                             allow_partial_runtime=True)
        self.report.write_text(json.dumps(report))
        self.put(self.target, "hypr/custom/rules.lua", "concurrent live edit")
        with self.assertRaisesRegex(ValueError, "Live drift"):
            deploy.apply(self.source, self.target, self.baseline, self.report, self.backup,
                         allow_partial_runtime=True)
        self.assertFalse(self.backup.exists())

    def test_rollback_refuses_drift_before_any_restore(self):
        self.put(self.source, "quickshell/ii/new.qml", "new")
        self.validate()
        self.apply()
        changed = self.put(self.target, "quickshell/ii/new.qml", "user edits")
        with self.assertRaisesRegex(ValueError, "Rollback would overwrite"):
            deploy.rollback(self.backup, True)
        self.assertEqual((self.target / "hypr/custom/rules.lua").read_text(), "after")
        self.assertEqual(changed.read_text(), "user edits")

    def test_rollback_verifies_backup(self):
        self.validate()
        self.apply()
        self.put(self.backup / "files", "hypr/custom/rules.lua", "corrupt")
        with self.assertRaisesRegex(ValueError, "Backup verification"):
            deploy.rollback(self.backup, True)
        self.assertEqual((self.target / "hypr/custom/rules.lua").read_text(), "after")

    def test_symlink_ancestors_cannot_redirect_target_writes(self):
        moved = self.root / "elsewhere"
        (self.target / "hypr").rename(moved)
        (self.target / "hypr").symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Unsafe path ancestor"):
            deploy.plan(self.source, self.target, self.baseline)

    def test_new_source_path_does_not_overwrite_new_live_file(self):
        self.put(self.source, "hypr/new.lua", "staged")
        self.put(self.target, "hypr/new.lua", "created after baseline")
        self.assertEqual(deploy.plan(self.source, self.target, self.baseline)["drift"], ["hypr/new.lua"])

    def test_partial_apply_can_be_rolled_back(self):
        self.put(self.source, "quickshell/ii/new.qml", "new")
        self.validate()
        self.apply()
        # Simulate a transaction interrupted before its second write.
        (self.target / "quickshell/ii/new.qml").unlink()
        deploy.rollback(self.backup, True)
        self.assertEqual((self.target / "hypr/custom/rules.lua").read_text(), "before")

    def test_drift_during_backup_prevents_first_live_write(self):
        self.validate()
        real_copy = deploy.atomic_copy

        def concurrent_edit(source, destination, expected):
            real_copy(source, destination, expected)
            self.put(self.source, "hypr/custom/rules.lua", "concurrent staged edit")

        with patch.object(deploy, "atomic_copy", side_effect=concurrent_edit):
            with self.assertRaisesRegex(ValueError, "changed during backup"):
                self.apply()
        self.assertEqual((self.target / "hypr/custom/rules.lua").read_text(), "before")

    def test_backup_cannot_be_inside_target(self):
        self.validate()
        with self.assertRaisesRegex(ValueError, "outside source and target"):
            deploy.apply(self.source, self.target, self.baseline, self.report, self.target / "backups")


if __name__ == "__main__":
    unittest.main()

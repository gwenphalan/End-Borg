#!/usr/bin/env python3
"""
Tests for AppImage normalization and deduplication logic.
Validates that multiple AppImage desktop entries for the same app
(e.g., T3 Code vs T3 Code Nightly 0.1.8-nightly...) correctly collapse into
a single canonical entry.
"""

import re
import unittest


def normalize_app_name(name: str) -> str:
    if not name:
        return ""
    name = re.sub(r"\s*\([^)]*(?:nightly|beta|alpha|rc|git)[^)]*\)", "", name, flags=re.I)
    name = re.sub(r"\s*\([^)]*[0-9]+[^)]*\)", "", name)
    name = re.sub(r"\s*v?[0-9]+(\.[0-9]+)+[-a-z0-9._]*", "", name, flags=re.I)
    return name.strip().lower()


def normalize_app_id(app_id: str) -> str:
    if not app_id:
        return ""
    app_id = re.sub(r"^appimagekit_[a-f0-9]+[-_]", "", app_id, flags=re.I)
    app_id = re.sub(r"\.desktop$", "", app_id, flags=re.I)
    app_id = re.sub(r"[-_](?:v?[0-9]+|nightly|beta|alpha|rc)[-_a-z0-9.]*$", "", app_id, flags=re.I)
    return re.sub(r"[-_]", "", app_id.lower())


def deduplicate_apps(entries):
    result_map = {}
    for app in entries:
        norm_name = normalize_app_name(app.get("name", ""))
        norm_id = normalize_app_id(app.get("id", ""))
        key = norm_name or norm_id or app.get("id", "")

        if key not in result_map:
            result_map[key] = app
        else:
            existing = result_map[key]
            existing_name = existing.get("name", "").strip().lower()
            current_name = app.get("name", "").strip().lower()

            existing_is_clean = (existing_name == norm_name)
            current_is_clean = (current_name == norm_name)

            if not existing_is_clean and current_is_clean:
                result_map[key] = app
            elif not existing_is_clean and not current_is_clean:
                if len(current_name) < len(existing_name):
                    result_map[key] = app

    return list(result_map.values())


class TestAppImageDeduplication(unittest.TestCase):
    def test_t3_code_duplicate_collapsing(self):
        entries = [
            {"id": "t3-code.desktop", "name": "T3 Code", "exec": "/home/user/Applications/t3.AppImage"},
            {
                "id": "appimagekit_9b581a8b-T3_Code_Nightly.desktop",
                "name": "T3 Code (Nightly) (0.1.8-nightly.20261104.4192)",
                "exec": "/home/user/Applications/t3-code-nightly.AppImage",
            },
        ]
        deduped = deduplicate_apps(entries)
        self.assertEqual(len(deduped), 1)
        self.assertEqual(deduped[0]["name"], "T3 Code")

    def test_version_stamped_entries(self):
        entries = [
            {"id": "obsidian-1.4.16.desktop", "name": "Obsidian 1.4.16", "exec": "/path/1"},
            {"id": "obsidian.desktop", "name": "Obsidian", "exec": "/path/2"},
        ]
        deduped = deduplicate_apps(entries)
        self.assertEqual(len(deduped), 1)
        self.assertEqual(deduped[0]["name"], "Obsidian")

    def test_distinct_apps_preserved(self):
        entries = [
            {"id": "t3-code.desktop", "name": "T3 Code"},
            {"id": "code.desktop", "name": "Visual Studio Code"},
            {"id": "firefox.desktop", "name": "Firefox"},
        ]
        deduped = deduplicate_apps(entries)
        self.assertEqual(len(deduped), 3)


if __name__ == "__main__":
    unittest.main()

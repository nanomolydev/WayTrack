#!/usr/bin/env python3
"""Собирает AltStore-совместимый sources JSON для LiveContainer."""
import json, os, datetime

repo = os.environ["REPO"]
owner = os.environ["OWNER"]
version = os.environ["VERSION"]
size = int(os.environ.get("SIZE", 0))
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S%z")
base = f"https://github.com/{repo}/releases"
download = f"{base}/download/v{version}/WayTrack.ipa"
description = "Таймлайн-планировщик: постоянные и активные задачи, циклы, отдыхи и перерывы."

version_entry = {
    "version": version,
    "date": date,
    "localizedDescription": description,
    "downloadURL": download,
    "size": size,
    "minOSVersion": "17.0",
}

manifest = {
    "name": "WayTrack",
    "identifier": "com.waytrack.source",
    "sourceURL": f"{base}/latest/download/repo.json",
    "apps": [{
        "name": "WayTrack",
        "bundleIdentifier": "com.waytrack.app",
        "developerName": owner,
        "subtitle": "Колба дня: циклы, отдыхи, перерывы",
        "localizedDescription": description,
        "iconURL": f"https://raw.githubusercontent.com/{repo}/main/Resources/Assets.xcassets/AppIcon.appiconset/icon.png",
        "tintColor": "FF9F0A",
        "category": "productivity",
        "screenshotURLs": [],
        # AltStore 1.x читает плоские поля, LiveContainer и AltStore 2.x — versions[]
        "version": version,
        "versionDate": date,
        "versionDescription": description,
        "downloadURL": download,
        "size": size,
        "versions": [version_entry],
    }],
    "news": [],
}

with open("repo.json", "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
print(json.dumps(manifest, ensure_ascii=False)[:400])

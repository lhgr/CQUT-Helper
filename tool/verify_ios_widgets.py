"""Validate the built app and WidgetKit extension before unsigned packaging."""

import argparse
import plistlib
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--ipa", type=Path)
    args = parser.parse_args()
    extension = args.app / "PlugIns" / "CQUTWidgetsExtension.appex"
    with (args.app / "Info.plist").open("rb") as source:
        app_info = plistlib.load(source)
    with (extension / "Info.plist").open("rb") as source:
        widget_info = plistlib.load(source)
    for key in ("CFBundleShortVersionString", "CFBundleVersion", "CQUTWidgetAppGroup"):
        value = app_info.get(key)
        if not isinstance(value, str) or not value or "$" in value:
            raise SystemExit(f"Runner has unresolved or missing {key}")
        if widget_info.get(key) != value:
            raise SystemExit(f"Runner and widget {key} differ")
    if widget_info.get("CFBundleIdentifier") != app_info["CFBundleIdentifier"] + ".CQUTWidgets":
        raise SystemExit("Widget bundle identifier does not match Runner")
    if widget_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
        raise SystemExit("Widget extension point is missing")
    if not (extension / widget_info["CFBundleExecutable"]).is_file():
        raise SystemExit("Widget executable is missing")
    if args.ipa:
        with zipfile.ZipFile(args.ipa) as archive:
            prefix = "Payload/Runner.app/"
            required_entries = (
                "Info.plist",
                "PlugIns/CQUTWidgetsExtension.appex/Info.plist",
                "PlugIns/CQUTWidgetsExtension.appex/" + widget_info["CFBundleExecutable"],
            )
            for relative in required_entries:
                if prefix + relative not in archive.namelist():
                    raise SystemExit(f"IPA is missing {relative}")
            for relative, expected in (("Info.plist", app_info), ("PlugIns/CQUTWidgetsExtension.appex/Info.plist", widget_info)):
                if plistlib.loads(archive.read(prefix + relative)) != expected:
                    raise SystemExit(f"IPA metadata differs from built app in {relative}")
            corrupt = archive.testzip()
            if corrupt:
                raise SystemExit(f"IPA contains a corrupt entry: {corrupt}")
    print("Validated Runner and embedded WidgetKit extension metadata")


if __name__ == "__main__":
    main()

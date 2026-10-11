#!/usr/bin/env python3
"""Configure a stable release signing key for generated Flutter Android scaffolding."""
from __future__ import annotations
import base64
import os
import re
from pathlib import Path

def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value.strip():
        raise SystemExit(f"Release publishing requires the GitHub Actions secret {name}.")
    if "\n" in value or "\r" in value:
        raise SystemExit(f"{name} must be a single-line value.")
    return value

def insert_after_plugins(text: str, code: str) -> str:
    match = re.search(r"(?s)\bplugins\s*\{.*?^\s*\}", text, re.M)
    if not match:
        raise SystemExit("Could not locate the plugins block in Android Gradle Kotlin DSL.")
    return text[:match.end()] + "\n\n" + code + text[match.end():]

def main() -> None:
    encoded = required("ANDROID_KEYSTORE_BASE64")
    store_password = required("ANDROID_KEYSTORE_PASSWORD")
    alias = required("ANDROID_KEY_ALIAS")
    key_password = required("ANDROID_KEY_PASSWORD")
    try:
        key = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        raise SystemExit("ANDROID_KEYSTORE_BASE64 is not valid base64.") from exc
    if len(key) < 1024:
        raise SystemExit("Decoded Android keystore is unexpectedly small.")
    app_dir = Path("android/app")
    app_dir.mkdir(parents=True, exist_ok=True)
    keystore = app_dir / "upload-keystore.jks"
    keystore.write_bytes(key)
    try:
        keystore.chmod(0o600)
    except OSError:
        pass

    def prop(v: str) -> str:
        return v.replace("\\", "\\\\").replace(":", "\\:").replace("=", "\\=").replace(" ", "\\ ")
    (Path("android") / "key.properties").write_text(
        "storePassword=" + prop(store_password) + "\n" +
        "keyPassword=" + prop(key_password) + "\n" +
        "keyAlias=" + prop(alias) + "\n" +
        "storeFile=app/upload-keystore.jks\n",
        encoding="utf-8",
    )
    gradle = Path("android/app/build.gradle.kts")
    if not gradle.exists():
        raise SystemExit("Expected android/app/build.gradle.kts after flutter create; refusing to publish without explicit signing configuration.")
    text = gradle.read_text(encoding="utf-8")
    if 'val keystorePropertiesFile = rootProject.file("key.properties")' not in text:
        code = '''val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}'''
        text = insert_after_plugins(text, code)
    if 'create("release")' not in text and 'create(\"release\")' not in text:
        match = re.search(r"(?m)^\s*buildTypes\s*\{", text)
        if not match:
            raise SystemExit("Could not locate android.buildTypes in generated Gradle file.")
        block = '''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
'''
        text = text[:match.start()] + block + text[match.start():]
    text = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                  'signingConfig = signingConfigs.getByName("release")', text)
    if 'signingConfig = signingConfigs.getByName("release")' not in text:
        match = re.search(r"(?m)^(\s*)release\s*\{", text)
        if not match:
            raise SystemExit("Could not locate release build type; refusing to create an update with unknown signing.")
        indent = match.group(1) + "    "
        pos = match.end()
        text = text[:pos] + "\n" + indent + 'signingConfig = signingConfigs.getByName("release")' + text[pos:]
    gradle.write_text(text, encoding="utf-8")
    print("Configured stable Android release signing using GitHub Actions secrets.")

if __name__ == "__main__":
    main()

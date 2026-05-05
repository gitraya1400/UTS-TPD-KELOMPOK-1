import sys
import subprocess
import os
from pathlib import Path

# =========================================================
# CONFIG ROOT PROJECT
# =========================================================
BASE_DIR = Path(__file__).resolve().parents[1]  # naik 1 level dari CODE/
CODE_DIR = BASE_DIR / "CODE"

TARGET_FOLDERS = [
    CODE_DIR / "EXTRACT",
    CODE_DIR / "TRANSFORM",
    CODE_DIR / "LOAD",
]

# =========================================================
# FUNCTION CONVERT 1 NOTEBOOK
# =========================================================
def convert_notebook(notebook_path):
    try:
        print(f"🔄 Converting: {notebook_path}")
        
        subprocess.run([
            sys.executable, "-m", "nbconvert",
            "--to", "script",
            str(notebook_path),
            "--output-dir", str(notebook_path.parent)
        ], check=True)

        print(f"  ✅ SUCCESS: {notebook_path.name}")

    except subprocess.CalledProcessError as e:
        print(f"  ❌ FAILED: {notebook_path.name}")
        print(f"     Error: {e}")

# =========================================================
# MAIN LOOP
# =========================================================
def main():
    print("🚀 START CONVERT NOTEBOOKS → PY\n")
    print(f"🐍 Python used: {sys.executable}\n")

    total = 0

    for folder in TARGET_FOLDERS:
        print(f"📂 Scanning folder: {folder}")

        if not folder.exists():
            print("  ⚠️ Folder tidak ditemukan, skip.\n")
            continue

        notebooks = list(folder.glob("*.ipynb"))

        if not notebooks:
            print("  ⚠️ Tidak ada notebook.\n")
            continue

        for nb in notebooks:
            convert_notebook(nb)
            total += 1

        print()

    print("====================================")
    print(f"🎯 DONE. Total converted: {total} file(s)")
    print("====================================")

# =========================================================
# ENTRY POINT
# =========================================================
if __name__ == "__main__":
    main()
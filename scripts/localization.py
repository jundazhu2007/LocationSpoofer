#!/usr/bin/env python3
"""多語言工具。

原文(繁體中文)即 key。本腳本會:
  1. 掃描 Sources/ 內所有含中文的字串字面值(跳過註解與 l10n:ignore 區段);
  2. 對照 Localization/translations.json,回報缺漏或多餘的翻譯;
  3. 產生 Resources/{zh-Hant,en,ja}.lproj/Localizable.strings。

用法:
  python3 scripts/localization.py check      只檢查,有缺漏就以非 0 結束
  python3 scripts/localization.py generate   檢查並寫出 .strings
  python3 scripts/localization.py list       印出所有 key
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
TABLE = ROOT / "Localization" / "translations.json"
OUT = ROOT / "Resources"
LANGS = ["en", "ja"]
CJK = re.compile(r"[\u4e00-\u9fff]")
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n")

def scan():
    keys, problems = {}, []
    for path in sorted(SOURCES.rglob("*.swift")):
        if "Demo" in path.parts: continue      # 開發者工具,主控台訊息不需翻譯
        ignoring = False
        for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "l10n:ignore-begin" in line: ignoring = True
            elif "l10n:ignore" in line and "ignore-end" not in line: continue
            if ignoring:
                if "l10n:ignore-end" in line: ignoring = False
                continue
            code = line.split("//")[0] if line.lstrip().startswith("//") else line
            # 去掉行尾註解(粗略:忽略字串內的 //)
            code = re.sub(r'\s//[^"]*$', "", code)
            for m in LITERAL.finditer(code):
                text = m.group(1)
                if not CJK.search(text): continue
                if "\\(" in text:
                    problems.append(f"{path.relative_to(ROOT)}:{no}: 含插值的中文字面值,請改用 L(\"…%@…\", 值): {text[:50]}")
                    continue
                keys.setdefault(unescape(text), []).append(f"{path.relative_to(ROOT)}:{no}")
    return keys, problems

def spec_signature(s: str):
    return sorted(re.sub(r"\d+\$", "", m) for m in re.findall(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dfsu]", s))

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    keys, problems = scan()
    if cmd == "list":
        for k in keys: print(k)
        return 0
    table = json.loads(TABLE.read_text(encoding="utf-8")) if TABLE.exists() else {}

    missing = [k for k in keys if k not in table or any(not table[k].get(l) for l in LANGS)]
    unused = [k for k in table if k not in keys]
    bad_spec = [k for k in keys if k in table and any(table[k].get(l) and spec_signature(table[k][l]) != spec_signature(k) for l in LANGS)]

    for p in problems: print("✗", p)
    for k in missing: print("✗ 缺翻譯:", k.replace("\n", "\\n"))
    for k in bad_spec: print("✗ 格式符號與原文不一致:", k)
    for k in unused: print("· 多餘(原始碼已沒用到):", k)
    print(f"共 {len(keys)} 個字串,缺 {len(missing)},格式不符 {len(bad_spec)},多餘 {len(unused)},插值問題 {len(problems)}")
    ok = not (problems or missing or bad_spec)

    if cmd == "generate" and ok:
        def esc(s): return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        for lang, folder in [("zh-Hant", "zh-Hant"), ("en", "en"), ("ja", "ja")]:
            d = OUT / f"{folder}.lproj"; d.mkdir(parents=True, exist_ok=True)
            lines = ["/* 由 scripts/localization.py 產生,請改 Localization/translations.json */"]
            for k in sorted(keys):
                v = k if lang == "zh-Hant" else table[k][lang]
                lines.append(f'"{esc(k)}" = "{esc(v)}";')
            (d / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("已寫出", ", ".join(f"{f}.lproj" for _, f in [("", "zh-Hant"), ("", "en"), ("", "ja")]))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())

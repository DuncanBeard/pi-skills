#!/usr/bin/env python3
"""
Patch pi's interactive model picker to show context window + thinking levels.

Idempotent: detects the `pi-mod: model-picker-enrichment` marker and skips if
already patched. Re-run after `pi update --self`.
"""

import os
import sys
from pathlib import Path

MARKER = "// --- pi-mod: model-picker-enrichment ---"

HELPERS = '''// --- pi-mod: model-picker-enrichment ---
function _fmtCtx(n) {
    if (!n || typeof n !== "number") return "";
    if (n >= 1000000) return `${(n / 1000000).toFixed(n % 1000000 ? 1 : 0)}M`;
    if (n >= 1000) return `${Math.round(n / 1000)}K`;
    return `${n}`;
}
function _thinkingLevels(model) {
    if (!model || !model.reasoning) return [];
    const order = ["off", "minimal", "low", "medium", "high", "xhigh"];
    return order.filter((l) => {
        const v = model.thinkingLevelMap?.[l];
        if (v === null) return false;
        if (l === "xhigh") return v !== undefined;
        return true;
    });
}
function _topThinking(model) {
    const levels = _thinkingLevels(model);
    for (const l of ["xhigh", "high", "medium", "low", "minimal"]) {
        if (levels.includes(l)) return l;
    }
    return "";
}
// --- end pi-mod ---
'''

CANDIDATE_ROOTS = [
    Path(os.environ.get("ProgramData", "C:/ProgramData")) / "global-npm" / "node_modules",
    Path(os.environ.get("APPDATA", "")) / "npm" / "node_modules" if os.environ.get("APPDATA") else None,
    Path.home() / ".npm-global" / "lib" / "node_modules",
    Path("/usr/local/lib/node_modules"),
    Path("/opt/homebrew/lib/node_modules"),
]

REL_PATH = Path("@earendil-works/pi-coding-agent/dist/modes/interactive/components/model-selector.js")


def find_picker() -> Path | None:
    for root in CANDIDATE_ROOTS:
        if not root:
            continue
        p = root / REL_PATH
        if p.exists():
            return p
    return None


def patch(text: str) -> str:
    if MARKER in text:
        return text  # already patched

    # 1. Inject helpers after the last import
    import_anchor = 'import { keyHint } from "./keybinding-hints.js";'
    if import_anchor not in text:
        raise RuntimeError(f"could not find import anchor: {import_anchor}")
    text = text.replace(import_anchor, f"{import_anchor}\n{HELPERS}", 1)

    # 2. Patch the row builder
    old_row = (
        '            const isSelected = i === this.selectedIndex;\n'
        '            const isCurrent = modelsAreEqual(this.currentModel, item.model);\n'
        '            let line = "";\n'
        '            if (isSelected) {\n'
        '                const prefix = theme.fg("accent", "\u2192 ");\n'
        '                const modelText = `${item.id}`;\n'
        '                const providerBadge = theme.fg("muted", `[${item.provider}]`);\n'
        '                const checkmark = isCurrent ? theme.fg("success", " \u2713") : "";\n'
        '                line = `${prefix + theme.fg("accent", modelText)} ${providerBadge}${checkmark}`;\n'
        '            }\n'
        '            else {\n'
        '                const modelText = `  ${item.id}`;\n'
        '                const providerBadge = theme.fg("muted", `[${item.provider}]`);\n'
        '                const checkmark = isCurrent ? theme.fg("success", " \u2713") : "";\n'
        '                line = `${modelText} ${providerBadge}${checkmark}`;\n'
        '            }'
    )
    new_row = (
        '            const isSelected = i === this.selectedIndex;\n'
        '            const isCurrent = modelsAreEqual(this.currentModel, item.model);\n'
        '            // --- pi-mod: enrich row with context + top thinking level ---\n'
        '            const ctxStr = _fmtCtx(item.model.contextWindow);\n'
        '            const ctxBadge = ctxStr ? theme.fg("muted", ` ${ctxStr}`) : "";\n'
        '            const top = _topThinking(item.model);\n'
        '            const thinkBadge = top ? theme.fg("muted", ` \\u25B2${top}`) : "";\n'
        '            // --- end pi-mod ---\n'
        '            let line = "";\n'
        '            if (isSelected) {\n'
        '                const prefix = theme.fg("accent", "\u2192 ");\n'
        '                const modelText = `${item.id}`;\n'
        '                const providerBadge = theme.fg("muted", `[${item.provider}]`);\n'
        '                const checkmark = isCurrent ? theme.fg("success", " \u2713") : "";\n'
        '                line = `${prefix + theme.fg("accent", modelText)} ${providerBadge}${ctxBadge}${thinkBadge}${checkmark}`;\n'
        '            }\n'
        '            else {\n'
        '                const modelText = `  ${item.id}`;\n'
        '                const providerBadge = theme.fg("muted", `[${item.provider}]`);\n'
        '                const checkmark = isCurrent ? theme.fg("success", " \u2713") : "";\n'
        '                line = `${modelText} ${providerBadge}${ctxBadge}${thinkBadge}${checkmark}`;\n'
        '            }'
    )
    if old_row not in text:
        raise RuntimeError("could not find row-builder block; pi internals may have changed")
    text = text.replace(old_row, new_row, 1)

    # 3. Patch the bottom hint
    old_hint = (
        '        else {\n'
        '            const selected = this.filteredModels[this.selectedIndex];\n'
        '            this.listContainer.addChild(new Spacer(1));\n'
        '            this.listContainer.addChild(new Text(theme.fg("muted", `  Model Name: ${selected.model.name}`), 0, 0));\n'
        '        }'
    )
    new_hint = (
        '        else {\n'
        '            const selected = this.filteredModels[this.selectedIndex];\n'
        '            this.listContainer.addChild(new Spacer(1));\n'
        '            this.listContainer.addChild(new Text(theme.fg("muted", `  Model Name: ${selected.model.name}`), 0, 0));\n'
        '            // --- pi-mod: detailed bottom hint ---\n'
        '            const m = selected.model;\n'
        '            const ctx = _fmtCtx(m.contextWindow) || "?";\n'
        '            const out = _fmtCtx(m.maxTokens) || "?";\n'
        '            const levels = _thinkingLevels(m);\n'
        '            const thinking = levels.length ? levels.join(", ") : "no";\n'
        '            const vision = Array.isArray(m.input) && m.input.includes("image") ? "yes" : "no";\n'
        '            this.listContainer.addChild(new Text(theme.fg("muted", `  Context: ${ctx}  Max out: ${out}  Thinking: ${thinking}  Vision: ${vision}`), 0, 0));\n'
        '            // --- end pi-mod ---\n'
        '        }'
    )
    if old_hint not in text:
        raise RuntimeError("could not find bottom-hint block; pi internals may have changed")
    text = text.replace(old_hint, new_hint, 1)

    return text


def main() -> int:
    picker = find_picker()
    if not picker:
        print("model-selector.js not found in any known install location", file=sys.stderr)
        return 1

    text = picker.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"already patched: {picker}")
        return 0

    try:
        patched = patch(text)
    except RuntimeError as e:
        print(f"patch failed: {e}", file=sys.stderr)
        print("pi internals may have shifted; the patch needs an update", file=sys.stderr)
        return 1

    backup = picker.with_suffix(picker.suffix + ".bak")
    backup.write_text(text, encoding="utf-8")
    picker.write_text(patched, encoding="utf-8")
    print(f"patched: {picker}")
    print(f"backup:  {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

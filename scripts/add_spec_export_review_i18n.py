#!/usr/bin/env python3
"""Batch-add SpecExport review sheet strings to Localizable.xcstrings (T50)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS = ROOT / "Reqeast" / "Localizable.xcstrings"

LOCALES = ("de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans", "zh-Hant")


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def simple(comment: str, translations: dict[str, str]) -> dict:
    return {
        "comment": comment,
        "localizations": {locale: unit(translations[locale]) for locale in LOCALES},
    }


def write_catalog(catalog: dict) -> None:
    text = json.dumps(catalog, ensure_ascii=False, indent=2)
    text = text.replace('": ', '" : ')
    XCSTRINGS.write_text(text + "\n", encoding="utf-8")


STRINGS: dict[str, dict] = {
    "Export Review": simple(
        "Title for the linked-project export review sheet.",
        {
            "de": "Export-Überprüfung",
            "es": "Revisión de exportación",
            "fr": "Révision d'exportation",
            "ja": "エクスポートの確認",
            "ko": "보내기 검토",
            "pt-BR": "Revisão de exportação",
            "zh-Hans": "导出审查",
            "zh-Hant": "匯出審查",
        },
    ),
    "Only in project": simple(
        "Export review segment for operations present locally but not in the on-disk spec.",
        {
            "de": "Nur im Projekt",
            "es": "Solo en el proyecto",
            "fr": "Uniquement dans le projet",
            "ja": "プロジェクトのみ",
            "ko": "프로젝트에만 있음",
            "pt-BR": "Somente no projeto",
            "zh-Hans": "仅在项目中",
            "zh-Hant": "僅在專案中",
        },
    ),
    "Only in spec": simple(
        "Export review segment for operations present in the on-disk spec but not locally.",
        {
            "de": "Nur in der Spec",
            "es": "Solo en la especificación",
            "fr": "Uniquement dans la spec",
            "ja": "仕様のみ",
            "ko": "사양에만 있음",
            "pt-BR": "Somente na especificação",
            "zh-Hans": "仅在规范中",
            "zh-Hant": "僅在規格中",
        },
    ),
    "Changed": simple(
        "Export review segment for operations changed between local state and on-disk spec.",
        {
            "de": "Geändert",
            "es": "Cambiado",
            "fr": "Modifié",
            "ja": "変更あり",
            "ko": "변경됨",
            "pt-BR": "Alterado",
            "zh-Hans": "已更改",
            "zh-Hant": "已變更",
        },
    ),
    "Conflicts": simple(
        "Export review segment for operations with local edits conflicting with the spec.",
        {
            "de": "Konflikte",
            "es": "Conflictos",
            "fr": "Conflits",
            "ja": "競合",
            "ko": "충돌",
            "pt-BR": "Conflitos",
            "zh-Hans": "冲突",
            "zh-Hant": "衝突",
        },
    ),
    "%lld only in project, %lld only in spec, %lld changed, %lld conflicts": simple(
        "VoiceOver summary of export review operation counts.",
        {
            "de": "%lld nur im Projekt, %lld nur in der Spec, %lld geändert, %lld Konflikte",
            "es": "%lld solo en el proyecto, %lld solo en la especificación, %lld cambiados, %lld conflictos",
            "fr": "%lld uniquement dans le projet, %lld uniquement dans la spec, %lld modifiés, %lld conflits",
            "ja": "プロジェクトのみ %lld、仕様のみ %lld、変更 %lld、競合 %lld",
            "ko": "프로젝트에만 %lld, 사양에만 %lld, 변경 %lld, 충돌 %lld",
            "pt-BR": "%lld somente no projeto, %lld somente na especificação, %lld alterados, %lld conflitos",
            "zh-Hans": "%lld 仅在项目中，%lld 仅在规范中，%lld 已更改，%lld 冲突",
            "zh-Hant": "%lld 僅在專案中，%lld 僅在規格中，%lld 已變更，%lld 衝突",
        },
    ),
    "No operations only in project": simple(
        "Empty state when the export review project-only segment has no rows.",
        {
            "de": "Keine Operationen nur im Projekt",
            "es": "No hay operaciones solo en el proyecto",
            "fr": "Aucune opération uniquement dans le projet",
            "ja": "プロジェクトのみの操作はありません",
            "ko": "프로젝트에만 있는 작업 없음",
            "pt-BR": "Nenhuma operação somente no projeto",
            "zh-Hans": "没有仅在项目中的操作",
            "zh-Hant": "沒有僅在專案中的操作",
        },
    ),
    "No operations only in spec": simple(
        "Empty state when the export review spec-only segment has no rows.",
        {
            "de": "Keine Operationen nur in der Spec",
            "es": "No hay operaciones solo en la especificación",
            "fr": "Aucune opération uniquement dans la spec",
            "ja": "仕様のみの操作はありません",
            "ko": "사양에만 있는 작업 없음",
            "pt-BR": "Nenhuma operação somente na especificação",
            "zh-Hans": "没有仅在规范中的操作",
            "zh-Hant": "沒有僅在規格中的操作",
        },
    ),
    "No changed operations": simple(
        "Empty state when the export review changed segment has no rows.",
        {
            "de": "Keine geänderten Operationen",
            "es": "No hay operaciones cambiadas",
            "fr": "Aucune opération modifiée",
            "ja": "変更された操作はありません",
            "ko": "변경된 작업 없음",
            "pt-BR": "Nenhuma operação alterada",
            "zh-Hans": "没有已更改的操作",
            "zh-Hant": "沒有已變更的操作",
        },
    ),
    "No conflicting operations": simple(
        "Empty state when the export review conflicts segment has no rows.",
        {
            "de": "Keine konfliktbehafteten Operationen",
            "es": "No hay operaciones en conflicto",
            "fr": "Aucune opération en conflit",
            "ja": "競合する操作はありません",
            "ko": "충돌하는 작업 없음",
            "pt-BR": "Nenhuma operação em conflito",
            "zh-Hans": "没有冲突的操作",
            "zh-Hant": "沒有衝突的操作",
        },
    ),
    "Use local version": simple(
        "Toggle label when export review keeps the user's local edits.",
        {
            "de": "Lokale Version verwenden",
            "es": "Usar versión local",
            "fr": "Utiliser la version locale",
            "ja": "ローカル版を使用",
            "ko": "로컬 버전 사용",
            "pt-BR": "Usar versão local",
            "zh-Hans": "使用本地版本",
            "zh-Hant": "使用本機版本",
        },
    ),
    "Align export to spec": simple(
        "Toggle label when export review aligns output to the on-disk spec.",
        {
            "de": "Export an Spec ausrichten",
            "es": "Alinear exportación con la especificación",
            "fr": "Aligner l'exportation sur la spec",
            "ja": "仕様に合わせてエクスポート",
            "ko": "사양에 맞게보내기",
            "pt-BR": "Alinhar exportação à especificação",
            "zh-Hans": "使导出与规范一致",
            "zh-Hant": "使匯出與規格一致",
        },
    ),
    "Exporting…": simple(
        "Progress label while the export review sheet serializes the spec file.",
        {
            "de": "Exportiere…",
            "es": "Exportando…",
            "fr": "Exportation…",
            "ja": "エクスポート中…",
            "ko": "보내는 중…",
            "pt-BR": "Exportando…",
            "zh-Hans": "正在导出…",
            "zh-Hant": "正在匯出…",
        },
    ),
}


def main() -> None:
    catalog = json.loads(XCSTRINGS.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})
    added = 0
    for key, entry in STRINGS.items():
        if key not in strings:
            added += 1
        strings[key] = entry
    write_catalog(catalog)
    print(f"Updated {len(STRINGS)} SpecExport review strings ({added} new keys)")


if __name__ == "__main__":
    main()
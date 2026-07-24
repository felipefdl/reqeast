#!/usr/bin/env python3
"""Batch-add SpecExport UI strings to Localizable.xcstrings (T49)."""

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
    "Export as OpenAPI...": simple(
        "Project context menu and File menu item to export the project as OpenAPI.",
        {
            "de": "Als OpenAPI exportieren…",
            "es": "Exportar como OpenAPI…",
            "fr": "Exporter en OpenAPI…",
            "ja": "OpenAPI としてエクスポート…",
            "ko": "OpenAPI로보내기…",
            "pt-BR": "Exportar como OpenAPI…",
            "zh-Hans": "导出为 OpenAPI…",
            "zh-Hant": "匯出為 OpenAPI…",
        },
    ),
    "Export as Postman...": simple(
        "Project context menu and File menu item to export the project as Postman.",
        {
            "de": "Als Postman exportieren…",
            "es": "Exportar como Postman…",
            "fr": "Exporter en Postman…",
            "ja": "Postman としてエクスポート…",
            "ko": "Postman으로보내기…",
            "pt-BR": "Exportar como Postman…",
            "zh-Hans": "导出为 Postman…",
            "zh-Hant": "匯出為 Postman…",
        },
    ),
    "Export Spec": simple(
        "Title for the spec export sheet.",
        {
            "de": "Spec exportieren",
            "es": "Exportar especificación",
            "fr": "Exporter la spécification",
            "ja": "仕様をエクスポート",
            "ko": "사양보내기",
            "pt-BR": "Exportar especificação",
            "zh-Hans": "导出规范",
            "zh-Hant": "匯出規格",
        },
    ),
    "Export format": simple(
        "Picker label for choosing OpenAPI or Postman export format.",
        {
            "de": "Exportformat",
            "es": "Formato de exportación",
            "fr": "Format d'exportation",
            "ja": "エクスポート形式",
            "ko": "보내기 형식",
            "pt-BR": "Formato de exportação",
            "zh-Hans": "导出格式",
            "zh-Hant": "匯出格式",
        },
    ),
    "OpenAPI format": simple(
        "Picker label for YAML or JSON when exporting OpenAPI.",
        {
            "de": "OpenAPI-Format",
            "es": "Formato OpenAPI",
            "fr": "Format OpenAPI",
            "ja": "OpenAPI 形式",
            "ko": "OpenAPI 형식",
            "pt-BR": "Formato OpenAPI",
            "zh-Hans": "OpenAPI 格式",
            "zh-Hant": "OpenAPI 格式",
        },
    ),
    "Include environments": simple(
        "Toggle to include API environments in the exported spec.",
        {
            "de": "Umgebungen einschließen",
            "es": "Incluir entornos",
            "fr": "Inclure les environnements",
            "ja": "環境を含める",
            "ko": "환경 포함",
            "pt-BR": "Incluir ambientes",
            "zh-Hans": "包含环境",
            "zh-Hant": "包含環境",
        },
    ),
    "Include deprecated and stale operations": simple(
        "Toggle to include deprecated and stale operations in the exported spec.",
        {
            "de": "Veraltete und stale Operationen einschließen",
            "es": "Incluir operaciones obsoletas y stale",
            "fr": "Inclure les opérations obsolètes et stale",
            "ja": "非推奨および stale の操作を含める",
            "ko": "사용 중단 및 stale 작업 포함",
            "pt-BR": "Incluir operações obsoletas e stale",
            "zh-Hans": "包含已弃用和 stale 的操作",
            "zh-Hant": "包含已棄用和 stale 的操作",
        },
    ),
    "Postman Collection": simple(
        "Segment label for Postman export format.",
        {
            "de": "Postman-Sammlung",
            "es": "Colección de Postman",
            "fr": "Collection Postman",
            "ja": "Postman コレクション",
            "ko": "Postman 컬렉션",
            "pt-BR": "Coleção Postman",
            "zh-Hans": "Postman 集合",
            "zh-Hant": "Postman 集合",
        },
    ),
    "OpenAPI 3.1": simple(
        "Summary label for OpenAPI export target version.",
        {
            "de": "OpenAPI 3.1",
            "es": "OpenAPI 3.1",
            "fr": "OpenAPI 3.1",
            "ja": "OpenAPI 3.1",
            "ko": "OpenAPI 3.1",
            "pt-BR": "OpenAPI 3.1",
            "zh-Hans": "OpenAPI 3.1",
            "zh-Hant": "OpenAPI 3.1",
        },
    ),
    "This project has no HTTP requests to export.": simple(
        "Error when a project has no exportable HTTP operations.",
        {
            "de": "Dieses Projekt enthält keine HTTP-Anfragen zum Exportieren.",
            "es": "Este proyecto no tiene solicitudes HTTP para exportar.",
            "fr": "Ce projet ne contient aucune requête HTTP à exporter.",
            "ja": "このプロジェクトにはエクスポートできる HTTP リクエストがありません。",
            "ko": "이 프로젝트에는보낼 HTTP 요청이 없습니다.",
            "pt-BR": "Este projeto não tem solicitações HTTP para exportar.",
            "zh-Hans": "此项目没有可导出的 HTTP 请求。",
            "zh-Hant": "此專案沒有可匯出的 HTTP 請求。",
        },
    ),
    "YAML": simple(
        "OpenAPI YAML file format label.",
        {
            "de": "YAML",
            "es": "YAML",
            "fr": "YAML",
            "ja": "YAML",
            "ko": "YAML",
            "pt-BR": "YAML",
            "zh-Hans": "YAML",
            "zh-Hant": "YAML",
        },
    ),
}


def main() -> None:
    catalog = json.loads(XCSTRINGS.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})
    added = 0
    for key, entry in STRINGS.items():
        if key not in strings:
            strings[key] = entry
            added += 1
        else:
            strings[key] = entry
    write_catalog(catalog)
    print(f"Updated {len(STRINGS)} SpecExport strings ({added} new keys)")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""Apply natural-phrasing fixes from translation audit (overwrite existing locales)."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS = ROOT / "Reqeast" / "Localizable.xcstrings"

LOCALES = ("de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans", "zh-Hant")


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def write_catalog(catalog: dict) -> None:
    text = json.dumps(catalog, ensure_ascii=False, indent=2)
    text = text.replace('": ', '" : ')
    XCSTRINGS.write_text(text + "\n", encoding="utf-8")


def stale_badge_fixes() -> dict[tuple[str, str], str]:
    """Toolbar badge plural variants: stale = out of sync with linked spec."""
    fixes: dict[tuple[str, str], str] = {}
    for n in range(11):
        key = f"Spec · {n} stale"
        fixes[(key, "pt-BR")] = f"Especificação · {n} desatualizada{'s' if n != 1 else ''}"
        fixes[(key, "ja")] = f"仕様 · 不一致 {n} 件"
        fixes[(key, "ko")] = f"사양 · 불일치 {n}개"
        fixes[(key, "es")] = f"Especificación · {n} obsoleta{'s' if n != 1 else ''}"
        fixes[(key, "fr")] = f"Spécification · {n} obsolète{'s' if n != 1 else ''}"

        key_r = f"Spec · {n} stale requests"
        fixes[(key_r, "pt-BR")] = f"Especificação · {n} requisição{'ões' if n != 1 else ''} desatualizada{'s' if n != 1 else ''}"
        fixes[(key_r, "ja")] = f"仕様 · {n} 件の仕様不一致リクエスト"
        fixes[(key_r, "ko")] = f"사양 · {n}개의 사양 제외 요청"
        fixes[(key_r, "es")] = f"Especificación · {n} solicitud{'es' if n != 1 else ''} obsoleta{'s' if n != 1 else ''}"
        fixes[(key_r, "fr")] = f"Spécification · {n} requête{'s' if n != 1 else ''} obsolète{'s' if n != 1 else ''}"

    fixes[("Spec · %lld stale", "pt-BR")] = "Especificação · %lld desatualizadas"
    fixes[("Spec · %lld stale", "ja")] = "仕様 · 不一致 %lld 件"
    fixes[("Spec · %lld stale", "ko")] = "사양 · 불일치 %lld개"
    fixes[("Spec · %lld stale requests", "pt-BR")] = "Especificação · %lld requisições desatualizadas"
    fixes[("Spec · %lld stale requests", "ja")] = "仕様 · %lld 件の仕様不一致リクエスト"
    fixes[("Spec · %lld stale requests", "ko")] = "사양 · %lld개의 사양 제외 요청"
    return fixes


# fmt: off
FIXUPS: dict[tuple[str, str], str] = {
    # --- pt-BR: stale semantics, anglicisms, on-disk ---
    ("Stale Requests", "pt-BR"): "Requisições desatualizadas",
    ("Delete Stale Requests", "pt-BR"): "Excluir requisições desatualizadas",
    ("Show Stale Only", "pt-BR"): "Mostrar apenas desatualizadas",
    ("Dismiss Stale", "pt-BR"): "Descartar desatualizada",
    ("Delete All Stale (%lld)", "pt-BR"): "Excluir todas as desatualizadas (%lld)",
    ("Dismiss All Stale (%lld)", "pt-BR"): "Descartar todas as desatualizadas (%lld)",
    ("No Stale Requests", "pt-BR"): "Nenhuma requisição desatualizada",
    ("No stale requests match your search.", "pt-BR"): "Nenhuma requisição desatualizada corresponde à sua busca.",
    ("Include deprecated and stale operations", "pt-BR"): "Incluir operações descontinuadas e desatualizadas",
    ("Imported", "pt-BR"): "Data de importação",
    ("Import HAR credentials as placeholders", "pt-BR"): "Importar credenciais HAR como marcadores",
    ("Spec Link", "pt-BR"): "Vínculo da especificação",
    ("Trusted Git Hosts", "pt-BR"): "Servidores Git confiáveis",
    ("Host %@ is not allowed. Add it under Settings → Trusted Git Hosts.", "pt-BR"): "O servidor %@ não é permitido. Adicione-o em Ajustes → Servidores Git confiáveis.",
    ("Host %@ is not trusted. Add it under Settings → Trusted Git Hosts to import from this server.", "pt-BR"): "O servidor %@ não é confiável. Adicione-o em Ajustes → Servidores Git confiáveis para importar deste servidor.",
    ("No trusted hosts configured.", "pt-BR"): "Nenhum servidor confiável configurado.",
    ("Could not find the on-disk spec for this project.", "pt-BR"): "Não foi possível encontrar a especificação local deste projeto.",
    ("Could not save spec file to disk.", "pt-BR"): "Não foi possível salvar o arquivo de especificação localmente.",
    ("Could not save the synced spec file to disk.", "pt-BR"): "Não foi possível salvar localmente o arquivo de especificação sincronizado.",
    ("Spec file is missing on disk and cannot be uploaded to iCloud.", "pt-BR"): "O arquivo de especificação local está ausente e não pode ser enviado ao iCloud.",
    ("Import secret values", "pt-BR"): "Importar valores de segredo",
    ("Import into", "pt-BR"): "Importar para",
    ("This project has no HTTP requests to export.", "pt-BR"): "Este projeto não tem requisições HTTP para exportar.",
    ("Configure OAuth2 endpoints and scopes. Token acquisition is not automated yet.", "pt-BR"): "Configure os endpoints e escopos do OAuth 2.0. A obtenção do token ainda não é automatizada.",
    ("HAR credentials as placeholders", "pt-BR"): "Credenciais HAR como marcadores de posição",
    ("Not Connected", "pt-BR"): "Não conectado",
    ("Not connected", "pt-BR"): "Não conectado",
    ("Connection Failed", "pt-BR"): "Falha na conexão",
    ("Invalid Configuration", "pt-BR"): "Configuração inválida",
    ("%lld cookies", "pt-BR"): "%lld cookies",

    # --- ja/ko: stale semantics, live source, export ---
    ("Stale Requests", "ja"): "仕様から外れたリクエスト",
    ("Stale Requests", "ko"): "사양에서 제외된 요청",
    ("Delete Stale Requests", "ja"): "仕様から外れたリクエストを削除",
    ("Delete Stale Requests", "ko"): "사양에서 제외된 요청 삭제",
    ("Dismiss Stale", "ja"): "仕様不一致を無視",
    ("Dismiss Stale", "ko"): "제외된 항목 무시",
    ("Delete All Stale (%lld)", "ja"): "仕様から外れた項目をすべて削除 (%lld)",
    ("Delete All Stale (%lld)", "ko"): "사양에서 제외된 항목 모두 삭제 (%lld)",
    ("Dismiss All Stale (%lld)", "ja"): "仕様不一致をすべて無視 (%lld)",
    ("Dismiss All Stale (%lld)", "ko"): "제외된 항목 모두 무시 (%lld)",
    ("Show Stale Only", "ja"): "仕様から外れた項目のみ表示",
    ("Show Stale Only", "ko"): "사양에서 제외된 항목만 표시",
    ("No Stale Requests", "ja"): "仕様から外れたリクエストはありません",
    ("No Stale Requests", "ko"): "사양에서 제외된 요청 없음",
    ("No stale requests match your search.", "ja"): "検索条件に一致する仕様不一致のリクエストはありません。",
    ("No stale requests match your search.", "ko"): "검색과 일치하는 사양에서 제외된 요청이 없습니다.",
    ("Include deprecated and stale operations", "ja"): "非推奨および仕様から外れた操作を含める",
    ("Include deprecated and stale operations", "ko"): "사용 중단 및 사양에서 제외된 작업 포함",
    ("Detached snapshot with no live source. Re-import the spec to refresh.", "ja"): "参照元にリンクされていません。仕様を再インポートして更新してください。",
    ("Detached snapshot with no live source. Re-import the spec to refresh.", "ko"): "연결된 원본에 연결되어 있지 않습니다. 사양을 다시 가져와 업데이트하세요.",
    ("Linked to %@. Use Check for updates to sync changes from the live spec.", "ja"): "%@ にリンクされています。「更新を確認」で参照元仕様の変更を同期してください。",
    ("Linked to %@. Use Check for updates to sync changes from the live spec.", "ko"): "%@에 연결되어 있습니다. 「업데이트 확인」으로 연결된 사양의 변경 사항을 동기화하세요.",
    ("This project has no live spec source to compare.", "ja"): "このプロジェクトには比較する参照元仕様がありません。",
    ("This project has no live spec source to compare.", "ko"): "이 프로젝트에는 비교할 연결된 사양 원본이 없습니다.",
    ("This project is not linked to a live spec source.", "ja"): "このプロジェクトは参照元仕様にリンクされていません。",
    ("This project is not linked to a live spec source.", "ko"): "이 프로젝트는 연결된 사양 원본에 연결되어 있지 않습니다.",
    ("This project is not linked to a live spec URL.", "ja"): "このプロジェクトは参照元仕様の URL にリンクされていません。",
    ("This project is not linked to a live spec URL.", "ko"): "이 프로젝트는 연결된 사양 URL에 연결되어 있지 않습니다.",
    ("This project uses a detached spec snapshot.", "ja"): "このプロジェクトは参照元にリンクされていない取り込み済み仕様を使用しています。",
    ("Git Provider Tokens", "ja"): "Git 提供元トークン",
    ("Git provider returned HTTP error %lld.", "ja"): "Git 提供元が HTTP エラー %lld を返しました。",
    ("No Git provider tokens configured.", "ja"): "Git 提供元トークンが設定されていません。",
    ("Received an invalid response from the Git provider.", "ja"): "Git 提供元から無効な応答を受信しました。",
    ("This Git provider is not supported.", "ja"): "この Git 提供元はサポートされていません。",
    ("Scaffold auth from spec", "ja"): "仕様から認証を自動生成",
    ("Scaffold auth from spec", "ko"): "사양에서 인증 자동 생성",
    ("Grant Type", "ja"): "認可タイプ",
    ("Import source", "ja"): "取り込み元",
    ("Source", "ja"): "取り込み元",
    ("No importable operations found in this spec.", "ja"): "この仕様にインポート可能な操作が見つかりませんでした。",
    ("No importable operations found in this spec.", "ko"): "이 사양에서 가져올 수 있는 작업을 찾지 못했습니다.",
    ("Could not find the on-disk spec for this project.", "ko"): "이 프로젝트에 저장된 사양을 디스크에서 찾을 수 없습니다.",
    ("Could not access the linked spec folder.", "ko"): "연결된 사양 폴더에 접근할 수 없습니다.",
    ("No Git provider tokens configured.", "ko"): "Git 제공자 토큰이 구성되어 있지 않습니다.",
    ("Background spec check", "ko"): "백그라운드에서 사양 확인",
    ("Choose spec bundle folder", "ja"): "複数ファイル仕様フォルダを選択",
    ("Choose spec bundle folder", "ko"): "다중 파일 사양 폴더 선택",
    ("Auth scaffold off", "ja"): "認証の自動生成：オフ",
    ("Auth scaffold on", "ja"): "認証の自動生成：オン",
    ("Auth scaffold off", "ko"): "인증 자동 생성: 끔",
    ("Auth scaffold on", "ko"): "인증 자동 생성: 켬",
    ("Request Failed", "ja"): "リクエストに失敗しました",

    # --- de: Live/Update loans, stale/deprecated distinction ---
    ("Remote fingerprint", "de"): "Fingerabdruck der Quelle",
    ("Linked to %@. Use Check for updates to sync changes from the live spec.", "de"): "Mit %@ verknüpft. Verwenden Sie Auf Updates prüfen, um Änderungen aus der verknüpften Spec zu synchronisieren.",
    ("Detached snapshot with no live source. Re-import the spec to refresh.", "de"): "Einmalimport ohne aktive Quelle. Spec erneut importieren, um zu aktualisieren.",
    ("This project has no live spec source to compare.", "de"): "Dieses Projekt hat keine aktive Spec-Quelle zum Vergleichen.",
    ("This project is not linked to a live spec source.", "de"): "Dieses Projekt ist nicht mit einer aktiven Spec-Quelle verknüpft.",
    ("This project is not linked to a live spec URL.", "de"): "Dieses Projekt ist nicht mit einer aktiven Spec-URL verknüpft.",
    ("This project uses a detached spec snapshot.", "de"): "Dieses Projekt verwendet einen einmaligen Spec-Import ohne aktive Verknüpfung.",
    ("Spec Sync Review", "de"): "Überprüfung der Spec-Synchronisation",
    ("Spec updates available", "de"): "Spec-Aktualisierungen verfügbar",
    ("Notify when the linked spec changes. Updates are never applied automatically.", "de"): "Benachrichtigen, wenn sich die verknüpfte Spec ändert. Aktualisierungen werden niemals automatisch angewendet.",
    ("Update available. Review changes to refresh.", "de"): "Aktualisierung verfügbar. Änderungen prüfen, um zu aktualisieren.",
    ("Include deprecated and stale operations", "de"): "Als veraltet markierte und aus der Spec entfernte Operationen einschließen",
    ("Include deprecated operations", "de"): "Als veraltet markierte Operationen einschließen",
    ("Deprecated excluded", "de"): "Als veraltet markierte ausgeschlossen",
    ("Deprecated included", "de"): "Als veraltet markierte enthalten",
    ("Invalid Configuration", "de"): "Ungültige Konfiguration",
    ("This applies to all devices signed into the same iCloud account.", "de"): "Dies gilt für alle Geräte, die mit demselben iCloud-Konto angemeldet sind.",
    ("Request History", "de"): "Anfrageverlauf",
    ("Auth scaffold off", "de"): "Auth-Vorlage aus",
    ("Auth scaffold on", "de"): "Auth-Vorlage an",
    ("Aggregation", "de"): "Aggregierung",
    ("Body", "de"): "Nachrichtentext",

    # --- es: stale grammar, accents, deprecated vs stale ---
    ("Include deprecated and stale operations", "es"): "Incluir operaciones obsoletas y eliminadas de la especificación",
    ("Dismiss Stale", "es"): "Descartar solicitud obsoleta",
    ("Delete All Stale (%lld)", "es"): "Eliminar todas las solicitudes obsoletas (%lld)",
    ("Dismiss All Stale (%lld)", "es"): "Descartar todas las solicitudes obsoletas (%lld)",
    ("Show Stale Only", "es"): "Mostrar solo solicitudes obsoletas",
    ("Connection Failed", "es"): "Conexión fallida",
    ("Invalid Configuration", "es"): "Configuración no válida",
    ("New project", "es"): "Nuevo proyecto",
    ("New Project", "es"): "Nuevo proyecto",
    ("Body Tab", "es"): "Pestaña Cuerpo",
    ("%lld cookies", "es"): "%lld cookies",
    ("Tokens are stored in Keychain on this device only and are used when refreshing linked Git specs. Sign in with GitHub uses the device authorization flow; you can also paste a personal access token manually.", "es"): "Los tokens se almacenan en Keychain solo en este dispositivo y se usan al actualizar especificaciones vinculadas en Git. Iniciar sesión con GitHub usa el flujo de autorización del dispositivo; también puede pegar un token de acceso personal manualmente.",

    # --- fr: spec → spécification, accents, scaffold ---
    ("%@ has spec changes. Open Reqeast to review and apply them.", "fr"): "%@ a des modifications de la spécification. Ouvrez Reqeast pour les examiner et les appliquer.",
    ("%lld only in project, %lld only in spec, %lld changed, %lld conflicts", "fr"): "%lld uniquement dans le projet, %lld uniquement dans la spécification, %lld modifiés, %lld conflits",
    ("Align export to spec", "fr"): "Aligner l'exportation sur la spécification",
    ("Background spec check", "fr"): "Vérification de la spécification en arrière-plan",
    ("Link to spec after import", "fr"): "Lier à la spécification après l'importation",
    ("Linked to %@. Use Check for updates to sync changes from the live spec.", "fr"): "Lié à %@. Utilisez Vérifier les mises à jour pour synchroniser les modifications de la spécification active.",
    ("No operations only in spec", "fr"): "Aucune opération uniquement dans la spécification",
    ("Notify when the linked spec changes. Updates are never applied automatically.", "fr"): "Notifier lorsque la spécification liée change. Les mises à jour ne sont jamais appliquées automatiquement.",
    ("Only in spec", "fr"): "Uniquement dans la spécification",
    ("Spec file is unavailable on this device. Requests are read-only until the spec can be downloaded from iCloud or the source URL.", "fr"): "Le fichier de spécification n'est pas disponible sur cet appareil. Les requêtes sont en lecture seule jusqu'à ce que la spécification puisse être téléchargée depuis iCloud ou l'URL source.",
    ("Spec updates available", "fr"): "Mises à jour de la spécification disponibles",
    ("Spec URL", "fr"): "URL de la spécification",
    ("This project has no live spec source to compare.", "fr"): "Ce projet n'a pas de source de spécification active à comparer.",
    ("This project is not linked to a live spec source.", "fr"): "Ce projet n'est pas lié à une source de spécification active.",
    ("Tokens are stored in Keychain on this device only and are used when refreshing linked Git specs. Sign in with GitHub uses the device authorization flow; you can also paste a personal access token manually.", "fr"): "Les jetons sont stockés dans Keychain sur cet appareil uniquement et sont utilisés lors de l'actualisation des spécifications Git liées. La connexion avec GitHub utilise le flux d'autorisation de l'appareil ; vous pouvez aussi coller un jeton d'accès personnel manuellement.",
    ("Include deprecated and stale operations", "fr"): "Inclure les opérations obsolètes et supprimées de la spécification",
    ("Connection Failed", "fr"): "Connexion échouée",
    ("Not Connected", "fr"): "Non connecté",
    ("This applies to all devices signed into the same iCloud account.", "fr"): "Cela s'applique à tous les appareils connectés au même compte iCloud.",
    ("Auth scaffold off", "fr"): "Génération d'authentification désactivée",
    ("Auth scaffold on", "fr"): "Génération d'authentification activée",
    ("Prettify", "fr"): "Formater",
    ("Body Tab", "fr"): "Onglet Corps",
    ("%lld cookies", "fr"): "%lld cookies",

    # --- zh-Hans ---
    ("Detached", "zh-Hans"): "未链接",
    ("Detached snapshot with no live source. Re-import the spec to refresh.", "zh-Hans"): "未链接到在线来源。请重新导入规范以更新。",
    ("Detached snapshot. Re-import the spec to refresh from a URL.", "zh-Hans"): "未链接导入。请重新导入规范以从 URL 更新。",
    ("Linked to %@. Use Check for updates to sync changes from the live spec.", "zh-Hans"): "已链接到 %@。使用“检查更新”同步联机规范的变更。",
    ("This project has no live spec source to compare.", "zh-Hans"): "此项目没有可比较的联机规范来源。",
    ("This project is not linked to a live spec source.", "zh-Hans"): "此项目未链接到联机规范来源。",
    ("This project is not linked to a live spec URL.", "zh-Hans"): "此项目未链接到联机规范 URL。",
    ("This project uses a detached spec snapshot.", "zh-Hans"): "此项目使用的是未链接来源的导入规范。",
    ("No requests were removed from the linked spec.", "zh-Hans"): "没有从已链接规范中移除的请求。",
    ("These requests were removed from the linked spec. This action cannot be undone.", "zh-Hans"): "这些请求已从已链接规范中移除。此操作无法撤销。",
    ("Auth scaffold off", "zh-Hans"): "认证模板已关闭",
    ("Auth scaffold on", "zh-Hans"): "认证模板已开启",
    ("Scaffold auth from spec", "zh-Hans"): "根据规范生成认证模板",
    ("No OpenAPI entry file found in the linked folder.", "zh-Hans"): "在已链接的文件夹中未找到 OpenAPI 主文件。",
    ("No OpenAPI entry file found in the selected folder. Expected openapi.yaml, openapi.json, or swagger.yaml.", "zh-Hans"): "在所选文件夹中未找到 OpenAPI 主文件。需要 openapi.yaml、openapi.json 或 swagger.yaml。",
    ("Could not find the on-disk spec for this project.", "zh-Hans"): "找不到此项目的本地规范。",
    ("Could not save spec file to disk.", "zh-Hans"): "无法将规范文件保存到本地。",
    ("Could not save the synced spec file to disk.", "zh-Hans"): "无法将同步的规范文件保存到本地。",
    ("Spec file is missing on disk and cannot be uploaded to iCloud.", "zh-Hans"): "本地规范文件缺失，无法上传到 iCloud。",
    ("Update available. Review changes to refresh.", "zh-Hans"): "有可用更新。请查看变更并更新。",
    ("Export Review", "zh-Hans"): "导出预览",
    ("Spec Sync Review", "zh-Hans"): "规范同步预览",
    ("Git Provider Tokens", "zh-Hans"): "Git 提供者令牌",
    ("Git provider returned HTTP error %lld.", "zh-Hans"): "Git 提供者返回 HTTP 错误 %lld。",
    ("No Git provider tokens configured.", "zh-Hans"): "未配置 Git 提供者令牌。",
    ("Received an invalid response from the Git provider.", "zh-Hans"): "收到来自 Git 提供者的无效响应。",
    ("This Git provider is not supported.", "zh-Hans"): "不支持此 Git 提供者。",
    ("One entry per line, format: key:value", "zh-Hans"): "每行一个条目，格式：键:值",

    # --- zh-Hant ---
    ("Detached", "zh-Hant"): "未連結",
    ("Background spec check", "zh-Hant"): "後台規格檢查",
    ("Detached snapshot with no live source. Re-import the spec to refresh.", "zh-Hant"): "未連結到線上來源。請重新匯入規格以更新。",
    ("Linked to %@. Use Check for updates to sync changes from the live spec.", "zh-Hant"): "已連結至 %@。使用「檢查更新」同步線上規格的變更。",
    ("This project has no live spec source to compare.", "zh-Hant"): "此專案沒有可比較的線上規格來源。",
    ("This project is not linked to a live spec source.", "zh-Hant"): "此專案未連結至線上規格來源。",
    ("This project is not linked to a live spec URL.", "zh-Hant"): "此專案未連結到線上規格 URL。",
    ("This project uses a detached spec snapshot.", "zh-Hant"): "此專案使用的是未連結來源的匯入規格。",
    ("No requests were removed from the linked spec.", "zh-Hant"): "沒有從已連結規格中移除的請求。",
    ("These requests were removed from the linked spec. This action cannot be undone.", "zh-Hant"): "這些請求已從已連結規格中移除。此操作無法復原。",
    ("Auth scaffold off", "zh-Hant"): "驗證範本已關閉",
    ("Auth scaffold on", "zh-Hant"): "驗證範本已開啟",
    ("Scaffold auth from spec", "zh-Hant"): "依規格產生驗證範本",
    ("No OpenAPI entry file found in the linked folder.", "zh-Hant"): "在已連結的資料夾中未找到 OpenAPI 主檔案。",
    ("No OpenAPI entry file found in the selected folder. Expected openapi.yaml, openapi.json, or swagger.yaml.", "zh-Hant"): "在所選資料夾中未找到 OpenAPI 主檔案。需要 openapi.yaml、openapi.json 或 swagger.yaml。",
    ("Could not find the on-disk spec for this project.", "zh-Hant"): "找不到此專案的本地規格。",
    ("Could not save spec file to disk.", "zh-Hant"): "無法將規格檔案儲存到本地。",
    ("Could not save the synced spec file to disk.", "zh-Hant"): "無法將同步的規格檔案儲存到本地。",
    ("Spec file is missing on disk and cannot be uploaded to iCloud.", "zh-Hant"): "本地規格檔案遺失，無法上傳到 iCloud。",
    ("Update available. Review changes to refresh.", "zh-Hant"): "有可用更新。請查看變更並更新。",
    ("Disconnected [%u]: %@", "zh-Hant"): "已斷線 [%u]：%@",
    ("One entry per line, format: key:value", "zh-Hant"): "每行一個項目，格式：鍵:值",
}
# fmt: on

FIXUPS.update(stale_badge_fixes())

# French values that still contain bare "spec" as a word (not spécification / OpenAPI).
FR_SPEC_RE = re.compile(r"\b(spec|Spec)\b(?![a-zA-Z])")


def patch_french_spec_values(catalog: dict) -> int:
    patched = 0
    for key, entry in catalog["strings"].items():
        loc = entry.get("localizations", {}).get("fr", {})
        unit_entry = loc.get("stringUnit", {})
        value = unit_entry.get("value")
        if not value or "spécification" in value.lower():
            continue
        if "openapi" in value.lower() and "spec" not in value.lower().replace("spécification", ""):
            continue

        def repl(match: re.Match[str]) -> str:
            word = match.group(1)
            return "spécification" if word == "spec" else "Spécification"

        new_value = FR_SPEC_RE.sub(repl, value)
        if new_value != value:
            unit_entry["value"] = new_value
            patched += 1
    return patched


def main() -> None:
    catalog = json.loads(XCSTRINGS.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    applied = 0
    missing = []

    for (key, locale), value in FIXUPS.items():
        if key not in strings:
            missing.append(key)
            continue
        strings[key].setdefault("localizations", {})[locale] = unit(value)
        applied += 1

    fr_patched = patch_french_spec_values(catalog)

    write_catalog(catalog)
    print(f"Applied {applied} fixups ({len(missing)} missing keys)")
    if missing:
        unique = sorted(set(missing))
        print("Missing:", ", ".join(unique[:20]), ("..." if len(unique) > 20 else ""))
    print(f"Patched {fr_patched} additional French spec→spécification values")


if __name__ == "__main__":
    main()
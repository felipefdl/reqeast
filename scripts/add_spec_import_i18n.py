#!/usr/bin/env python3
"""Batch-add SpecImport UI strings to Localizable.xcstrings (T18)."""

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


def plural(comment: str, translations: dict[str, dict[str, str]]) -> dict:
    localizations = {}
    for locale in LOCALES:
        forms = translations[locale]
        localizations[locale] = {
            "variations": {
                "plural": {form: unit(value) for form, value in forms.items()}
            }
        }
    return {"comment": comment, "localizations": localizations}


def write_catalog(catalog: dict) -> None:
    """Write xcstrings using Xcode-style spacing (`"key" :`)."""
    text = json.dumps(catalog, ensure_ascii=False, indent=2)
    text = text.replace('": ', '" : ')
    XCSTRINGS.write_text(text + "\n", encoding="utf-8")


# fmt: off
STRINGS: dict[str, dict] = {
    # Entry points — distinct from Import Project
    "Import Spec": simple(
        "Title for the spec import sheet and entry-point buttons.",
        {
            "de": "Spec importieren",
            "es": "Importar especificación",
            "fr": "Importer la spécification",
            "ja": "仕様をインポート",
            "ko": "사양 가져오기",
            "pt-BR": "Importar especificação",
            "zh-Hans": "导入规范",
            "zh-Hant": "匯入規格",
        },
    ),
    "Import Spec...": simple(
        "Menu item to open the spec import sheet.",
        {
            "de": "Spec importieren…",
            "es": "Importar especificación…",
            "fr": "Importer la spécification…",
            "ja": "仕様をインポート…",
            "ko": "사양 가져오기…",
            "pt-BR": "Importar especificação…",
            "zh-Hans": "导入规范…",
            "zh-Hant": "匯入規格…",
        },
    ),
    "Import Preview": simple(
        "Navigation title while reviewing a parsed spec before import.",
        {
            "de": "Importvorschau",
            "es": "Vista previa de importación",
            "fr": "Aperçu de l'importation",
            "ja": "インポートのプレビュー",
            "ko": "가져오기 미리보기",
            "pt-BR": "Pré-visualização da importação",
            "zh-Hans": "导入预览",
            "zh-Hant": "匯入預覽",
        },
    ),

    # Sheet actions
    "Try Again": simple(
        "Button to return to source selection after a spec import error.",
        {
            "de": "Erneut versuchen",
            "es": "Intentar de nuevo",
            "fr": "Réessayer",
            "ja": "再試行",
            "ko": "다시 시도",
            "pt-BR": "Tentar novamente",
            "zh-Hans": "重试",
            "zh-Hant": "重試",
        },
    ),
    "Choose File": simple(
        "Button to open a file picker for spec import.",
        {
            "de": "Datei auswählen",
            "es": "Elegir archivo",
            "fr": "Choisir un fichier",
            "ja": "ファイルを選択",
            "ko": "파일 선택",
            "pt-BR": "Escolher arquivo",
            "zh-Hans": "选择文件",
            "zh-Hant": "選擇檔案",
        },
    ),
    "Fetch": simple(
        "Button to download a spec from an HTTPS URL.",
        {
            "de": "Abrufen",
            "es": "Obtener",
            "fr": "Récupérer",
            "ja": "取得",
            "ko": "가져오기",
            "pt-BR": "Buscar",
            "zh-Hans": "获取",
            "zh-Hant": "取得",
        },
    ),
    "Continue": simple(
        "Button to continue spec import from pasted content.",
        {
            "de": "Weiter",
            "es": "Continuar",
            "fr": "Continuer",
            "ja": "続ける",
            "ko": "계속",
            "pt-BR": "Continuar",
            "zh-Hans": "继续",
            "zh-Hant": "繼續",
        },
    ),

    # Source picker
    "Source": simple(
        "Segmented control label for spec import source type.",
        {
            "de": "Quelle",
            "es": "Origen",
            "fr": "Source",
            "ja": "ソース",
            "ko": "소스",
            "pt-BR": "Origem",
            "zh-Hans": "来源",
            "zh-Hant": "來源",
        },
    ),
    "URL": simple(
        "Spec import source tab for HTTPS URLs.",
        {
            "de": "URL",
            "es": "URL",
            "fr": "URL",
            "ja": "URL",
            "ko": "URL",
            "pt-BR": "URL",
            "zh-Hans": "URL",
            "zh-Hant": "URL",
        },
    ),
    "Paste": simple(
        "Spec import source tab for pasted YAML or JSON.",
        {
            "de": "Einfügen",
            "es": "Pegar",
            "fr": "Coller",
            "ja": "貼り付け",
            "ko": "붙여넣기",
            "pt-BR": "Colar",
            "zh-Hans": "粘贴",
            "zh-Hant": "貼上",
        },
    ),

    # Source descriptions
    "Import an OpenAPI or API spec from a file on your device.": simple(
        "Description for file-based spec import.",
        {
            "de": "Importieren Sie eine OpenAPI- oder API-Spezifikation von Ihrem Gerät.",
            "es": "Importa una especificación OpenAPI o de API desde un archivo en tu dispositivo.",
            "fr": "Importez une spécification OpenAPI ou API depuis un fichier sur votre appareil.",
            "ja": "デバイス上のファイルから OpenAPI または API 仕様をインポートします。",
            "ko": "기기의 파일에서 OpenAPI 또는 API 사양을 가져옵니다.",
            "pt-BR": "Importe uma especificação OpenAPI ou de API de um arquivo no seu dispositivo.",
            "zh-Hans": "从设备上的文件导入 OpenAPI 或其他 API 规范。",
            "zh-Hant": "從裝置上的檔案匯入 OpenAPI 或其他 API 規格。",
        },
    ),
    "Supported formats: YAML, YML, JSON": simple(
        "Supported file extensions for spec import.",
        {
            "de": "Unterstützte Formate: YAML, YML, JSON",
            "es": "Formatos compatibles: YAML, YML, JSON",
            "fr": "Formats pris en charge : YAML, YML, JSON",
            "ja": "対応形式：YAML、YML、JSON",
            "ko": "지원 형식: YAML, YML, JSON",
            "pt-BR": "Formatos suportados: YAML, YML, JSON",
            "zh-Hans": "支持的格式：YAML、YML、JSON",
            "zh-Hant": "支援的格式：YAML、YML、JSON",
        },
    ),
    "Fetch a spec over HTTPS. The import is a one-time snapshot.": simple(
        "Description for URL-based spec import.",
        {
            "de": "Spec über HTTPS abrufen. Der Import wird nicht mit der Quelle verknüpft.",
            "es": "Obtén una especificación por HTTPS. La importación no queda vinculada a la fuente.",
            "fr": "Récupérez une spécification via HTTPS. L'importation n'est pas liée à la source.",
            "ja": "HTTPS で仕様を取得します。インポートはソースとリンクされません。",
            "ko": "HTTPS로 사양을 가져옵니다. 가져오기는 소스와 연결되지 않습니다.",
            "pt-BR": "Busque uma especificação via HTTPS. A importação não fica vinculada à fonte.",
            "zh-Hans": "通过 HTTPS 获取规范。导入不会与来源保持链接。",
            "zh-Hant": "透過 HTTPS 取得規格。匯入不會與來源保持連結。",
        },
    ),
    "Only HTTPS URLs are supported. Maximum download size is 5 MiB.": simple(
        "URL import constraints for spec fetch.",
        {
            "de": "Nur HTTPS-URLs werden unterstützt. Maximale Downloadgröße: 5 MiB.",
            "es": "Solo se admiten URL HTTPS. El tamaño máximo de descarga es 5 MiB.",
            "fr": "Seules les URL HTTPS sont prises en charge. Taille maximale du téléchargement : 5 Mio.",
            "ja": "HTTPS URL のみ対応しています。最大ダウンロードサイズは 5 MiB です。",
            "ko": "HTTPS URL만 지원됩니다. 최대 다운로드 크기는 5MiB입니다.",
            "pt-BR": "Somente URLs HTTPS são suportadas. O tamanho máximo de download é 5 MiB.",
            "zh-Hans": "仅支持 HTTPS URL。最大下载大小为 5 MiB。",
            "zh-Hant": "僅支援 HTTPS URL。最大下載大小為 5 MiB。",
        },
    ),
    "Paste OpenAPI YAML or JSON directly.": simple(
        "Description for paste-based spec import.",
        {
            "de": "OpenAPI-YAML oder JSON direkt einfügen.",
            "es": "Pega YAML o JSON de OpenAPI directamente.",
            "fr": "Collez directement du YAML ou JSON OpenAPI.",
            "ja": "OpenAPI の YAML または JSON を直接貼り付けます。",
            "ko": "OpenAPI YAML 또는 JSON을 직접 붙여넣습니다.",
            "pt-BR": "Cole YAML ou JSON OpenAPI diretamente.",
            "zh-Hans": "直接粘贴 OpenAPI YAML 或 JSON。",
            "zh-Hant": "直接貼上 OpenAPI YAML 或 JSON。",
        },
    ),

    # Loading states
    "Parsing Spec": simple(
        "Loading title while parsing a spec file.",
        {
            "de": "Spec wird analysiert",
            "es": "Analizando especificación",
            "fr": "Analyse de la spécification",
            "ja": "仕様を解析中",
            "ko": "사양 파싱 중",
            "pt-BR": "Analisando especificação",
            "zh-Hans": "正在解析规范",
            "zh-Hant": "正在解析規格",
        },
    ),
    "Reading operations and building a preview.": simple(
        "Loading subtitle while parsing a spec.",
        {
            "de": "Operationen werden gelesen und eine Vorschau erstellt.",
            "es": "Leyendo operaciones y generando una vista previa.",
            "fr": "Lecture des opérations et création d'un aperçu.",
            "ja": "オペレーションを読み込み、プレビューを作成しています。",
            "ko": "오퍼레이션을 읽고 미리보기를 생성하는 중입니다.",
            "pt-BR": "Lendo operações e gerando uma pré-visualização.",
            "zh-Hans": "正在读取操作并生成预览。",
            "zh-Hant": "正在讀取操作並建立預覽。",
        },
    ),
    "Importing": simple(
        "Loading title while committing a spec import.",
        {
            "de": "Importieren",
            "es": "Importando",
            "fr": "Importation",
            "ja": "インポート中",
            "ko": "가져오는 중",
            "pt-BR": "Importando",
            "zh-Hans": "正在导入",
            "zh-Hant": "正在匯入",
        },
    ),
    "Creating project, folders, and requests.": simple(
        "Loading subtitle while committing a spec import.",
        {
            "de": "Projekt, Ordner und Anfragen werden erstellt.",
            "es": "Creando proyecto, carpetas y solicitudes.",
            "fr": "Création du projet, des dossiers et des requêtes.",
            "ja": "プロジェクト、フォルダ、リクエストを作成しています。",
            "ko": "프로젝트, 폴더 및 요청을 생성하는 중입니다.",
            "pt-BR": "Criando projeto, pastas e requisições.",
            "zh-Hans": "正在创建项目、文件夹和请求。",
            "zh-Hant": "正在建立專案、資料夾和請求。",
        },
    ),

    # Preview
    "Updating preview…": simple(
        "Status while re-parsing a spec after option changes.",
        {
            "de": "Vorschau wird aktualisiert…",
            "es": "Actualizando vista previa…",
            "fr": "Mise à jour de l'aperçu…",
            "ja": "プレビューを更新中…",
            "ko": "미리보기 업데이트 중…",
            "pt-BR": "Atualizando pré-visualização…",
            "zh-Hans": "正在更新预览…",
            "zh-Hant": "正在更新預覽…",
        },
    ),
    "Snapshot from %@ at %@. Changes to the spec won't appear automatically.": simple(
        "Disclaimer for URL-imported specs showing host and fetch time.",
        {
            "de": "Importiert von %1$@ um %2$@. Änderungen an der Spec werden nicht automatisch übernommen.",
            "es": "Importado desde %1$@ el %2$@. Los cambios en la especificación no se reflejarán automáticamente.",
            "fr": "Importé depuis %1$@ le %2$@. Les modifications de la spécification n'apparaîtront pas automatiquement.",
            "ja": "%1$@ から %2$@ にインポートしました。仕様の変更は自動的に反映されません。",
            "ko": "%1$@에서 %2$@에 가져왔습니다. 사양 변경 사항은 자동으로 반영되지 않습니다.",
            "pt-BR": "Importado de %1$@ em %2$@. Alterações na especificação não serão aplicadas automaticamente.",
            "zh-Hans": "于 %2$@ 从 %1$@ 导入。规范的更改不会自动同步。",
            "zh-Hant": "於 %2$@ 從 %1$@ 匯入。規格的變更不會自動同步。",
        },
    ),
    "Folders (%lld)": simple(
        "Section header showing folder count in spec import preview.",
        {
            "de": "Ordner (%lld)",
            "es": "Carpetas (%lld)",
            "fr": "Dossiers (%lld)",
            "ja": "フォルダ (%lld)",
            "ko": "폴더 (%lld)",
            "pt-BR": "Pastas (%lld)",
            "zh-Hans": "文件夹 (%lld)",
            "zh-Hant": "資料夾 (%lld)",
        },
    ),
    "and %lld more": simple(
        "Truncated list suffix for folders in spec import preview.",
        {
            "de": "und %lld weitere",
            "es": "y %lld más",
            "fr": "et %lld de plus",
            "ja": "他 %lld 件",
            "ko": "외 %lld개",
            "pt-BR": "e mais %lld",
            "zh-Hans": "还有 %lld 个",
            "zh-Hant": "還有 %lld 個",
        },
    ),
    "and %lld more warnings": simple(
        "Truncated list suffix for warnings in spec import preview.",
        {
            "de": "und %lld weitere Warnungen",
            "es": "y %lld advertencias más",
            "fr": "et %lld avertissements de plus",
            "ja": "他 %lld 件の警告",
            "ko": "외 %lld개의 경고",
            "pt-BR": "e mais %lld avisos",
            "zh-Hans": "还有 %lld 条警告",
            "zh-Hant": "還有 %lld 則警告",
        },
    ),

    # Pluralized counts
    "%lld warnings": plural(
        "Warning count label in spec import preview.",
        {
            "de": {"one": "1 Warnung", "other": "%lld Warnungen"},
            "es": {"one": "1 advertencia", "other": "%lld advertencias"},
            "fr": {"one": "1 avertissement", "other": "%lld avertissements"},
            "ja": {"other": "%lld 件の警告"},
            "ko": {"other": "경고 %lld개"},
            "pt-BR": {"one": "1 aviso", "other": "%lld avisos"},
            "zh-Hans": {"other": "%lld 条警告"},
            "zh-Hant": {"other": "%lld 則警告"},
        },
    ),
    "1 operation": simple(
        "Singular operation count in spec import preview.",
        {
            "de": "1 Operation",
            "es": "1 operación",
            "fr": "1 opération",
            "ja": "1 件のオペレーション",
            "ko": "오퍼레이션 1개",
            "pt-BR": "1 operação",
            "zh-Hans": "1 个操作",
            "zh-Hant": "1 個操作",
        },
    ),
    "%lld operations": plural(
        "Pluralized operation count in spec import preview.",
        {
            "de": {"one": "1 Operation", "other": "%lld Operationen"},
            "es": {"one": "1 operación", "other": "%lld operaciones"},
            "fr": {"one": "1 opération", "other": "%lld opérations"},
            "ja": {"other": "%lld 件のオペレーション"},
            "ko": {"other": "오퍼레이션 %lld개"},
            "pt-BR": {"one": "1 operação", "other": "%lld operações"},
            "zh-Hans": {"other": "%lld 个操作"},
            "zh-Hant": {"other": "%lld 個操作"},
        },
    ),
    "%@ of %@": simple(
        "Byte count indicator for pasted spec content (current of limit).",
        {
            "de": "%1$@ von %2$@",
            "es": "%1$@ de %2$@",
            "fr": "%1$@ sur %2$@",
            "ja": "%1$@ / %2$@",
            "ko": "%1$@ / %2$@",
            "pt-BR": "%1$@ de %2$@",
            "zh-Hans": "%1$@ / %2$@",
            "zh-Hant": "%1$@ / %2$@",
        },
    ),

    # Advanced options
    "Advanced": simple(
        "Collapsed disclosure group for spec import options.",
        {
            "de": "Erweitert",
            "es": "Avanzado",
            "fr": "Avancé",
            "ja": "詳細設定",
            "ko": "고급",
            "pt-BR": "Avançado",
            "zh-Hans": "高级",
            "zh-Hant": "進階",
        },
    ),
    "Request naming": simple(
        "Picker label for how imported requests are named.",
        {
            "de": "Anfragebenennung",
            "es": "Nombre de solicitudes",
            "fr": "Nom des requêtes",
            "ja": "リクエスト名",
            "ko": "요청 이름",
            "pt-BR": "Nome das requisições",
            "zh-Hans": "请求命名",
            "zh-Hant": "請求命名",
        },
    ),
    "Include deprecated operations": simple(
        "Toggle to include deprecated API operations.",
        {
            "de": "Veraltete Operationen einschließen",
            "es": "Incluir operaciones obsoletas",
            "fr": "Inclure les opérations obsolètes",
            "ja": "非推奨のオペレーションを含める",
            "ko": "사용 중단된 오퍼레이션 포함",
            "pt-BR": "Incluir operações obsoletas",
            "zh-Hans": "包含已弃用的操作",
            "zh-Hant": "包含已棄用的操作",
        },
    ),
    "Enable optional parameters": simple(
        "Toggle to enable optional API parameters on import.",
        {
            "de": "Optionale Parameter aktivieren",
            "es": "Habilitar parámetros opcionales",
            "fr": "Activer les paramètres facultatifs",
            "ja": "オプションパラメーターを有効にする",
            "ko": "선택적 매개변수 사용",
            "pt-BR": "Ativar parâmetros opcionais",
            "zh-Hans": "启用可选参数",
            "zh-Hant": "啟用選用參數",
        },
    ),
    "Scaffold auth from spec": simple(
        "Toggle to scaffold authentication placeholders from the spec.",
        {
            "de": "Authentifizierung aus Spec erstellen",
            "es": "Generar autenticación desde la especificación",
            "fr": "Créer l'authentification à partir de la spécification",
            "ja": "仕様から認証をスキャフォールド",
            "ko": "사양에서 인증 스캐폴딩",
            "pt-BR": "Criar autenticação a partir da especificação",
            "zh-Hans": "根据规范搭建认证",
            "zh-Hant": "依規格建立驗證",
        },
    ),
    "Create environments from servers": simple(
        "Toggle to create API environments from spec servers.",
        {
            "de": "Umgebungen aus Servern erstellen",
            "es": "Crear entornos desde servidores",
            "fr": "Créer des environnements à partir des serveurs",
            "ja": "サーバーから環境を作成",
            "ko": "서버에서 환경 생성",
            "pt-BR": "Criar ambientes a partir de servidores",
            "zh-Hans": "根据服务器创建环境",
            "zh-Hant": "依伺服器建立環境",
        },
    ),

    # Option summary chips
    "Tags": simple(
        "Folder strategy: organize by OpenAPI tags.",
        {
            "de": "Tags",
            "es": "Etiquetas",
            "fr": "Tags",
            "ja": "タグ",
            "ko": "태그",
            "pt-BR": "Tags",
            "zh-Hans": "标签",
            "zh-Hant": "標籤",
        },
    ),
    "Paths": simple(
        "Folder strategy: organize by URL paths.",
        {
            "de": "Pfade",
            "es": "Rutas",
            "fr": "Chemins",
            "ja": "パス",
            "ko": "경로",
            "pt-BR": "Caminhos",
            "zh-Hans": "路径",
            "zh-Hant": "路徑",
        },
    ),
    "Flat": simple(
        "Folder strategy: no subfolders.",
        {
            "de": "Flach",
            "es": "Plano",
            "fr": "Plat",
            "ja": "フラット",
            "ko": "단일",
            "pt-BR": "Plano",
            "zh-Hans": "扁平",
            "zh-Hant": "扁平",
        },
    ),
    "Summary": simple(
        "Request naming: use operation summary.",
        {
            "de": "Zusammenfassung",
            "es": "Resumen",
            "fr": "Résumé",
            "ja": "概要",
            "ko": "요약",
            "pt-BR": "Resumo",
            "zh-Hans": "摘要",
            "zh-Hant": "摘要",
        },
    ),
    "Operation ID": simple(
        "Request naming: use OpenAPI operationId.",
        {
            "de": "Operations-ID",
            "es": "ID de operación",
            "fr": "ID d'opération",
            "ja": "オペレーション ID",
            "ko": "오퍼레이션 ID",
            "pt-BR": "ID da operação",
            "zh-Hans": "操作 ID",
            "zh-Hant": "操作 ID",
        },
    ),
    "Method + Path": simple(
        "Request naming: HTTP method and path.",
        {
            "de": "Methode + Pfad",
            "es": "Método + ruta",
            "fr": "Méthode + chemin",
            "ja": "メソッド + パス",
            "ko": "메서드 + 경로",
            "pt-BR": "Método + caminho",
            "zh-Hans": "方法 + 路径",
            "zh-Hant": "方法 + 路徑",
        },
    ),
    "Deprecated included": simple(
        "Advanced options summary: deprecated operations included.",
        {
            "de": "Veraltete enthalten",
            "es": "Obsoletas incluidas",
            "fr": "Obsolètes incluses",
            "ja": "非推奨を含む",
            "ko": "사용 중단 포함",
            "pt-BR": "Obsoletas incluídas",
            "zh-Hans": "含已弃用",
            "zh-Hant": "含已棄用",
        },
    ),
    "Deprecated excluded": simple(
        "Advanced options summary: deprecated operations excluded.",
        {
            "de": "Veraltete ausgeschlossen",
            "es": "Obsoletas excluidas",
            "fr": "Obsolètes exclues",
            "ja": "非推奨を除外",
            "ko": "사용 중단 제외",
            "pt-BR": "Obsoletas excluídas",
            "zh-Hans": "不含已弃用",
            "zh-Hant": "不含已棄用",
        },
    ),
    "Optional params on": simple(
        "Advanced options summary: optional parameters enabled.",
        {
            "de": "Optionale Parameter an",
            "es": "Parámetros opcionales activados",
            "fr": "Paramètres facultatifs activés",
            "ja": "オプションパラメーター オン",
            "ko": "선택 매개변수 켜짐",
            "pt-BR": "Parâmetros opcionais ativados",
            "zh-Hans": "可选参数开",
            "zh-Hant": "選用參數開",
        },
    ),
    "Optional params off": simple(
        "Advanced options summary: optional parameters disabled.",
        {
            "de": "Optionale Parameter aus",
            "es": "Parámetros opcionales desactivados",
            "fr": "Paramètres facultatifs désactivés",
            "ja": "オプションパラメーター オフ",
            "ko": "선택 매개변수 꺼짐",
            "pt-BR": "Parâmetros opcionais desativados",
            "zh-Hans": "可选参数关",
            "zh-Hant": "選用參數關",
        },
    ),
    "Auth scaffold on": simple(
        "Advanced options summary: auth scaffolding enabled.",
        {
            "de": "Auth-Scaffold an",
            "es": "Autenticación generada activada",
            "fr": "Authentification créée activée",
            "ja": "認証スキャフォールド オン",
            "ko": "인증 스캐폴딩 켜짐",
            "pt-BR": "Autenticação gerada ativada",
            "zh-Hans": "认证脚手架开",
            "zh-Hant": "驗證鷹架開",
        },
    ),
    "Auth scaffold off": simple(
        "Advanced options summary: auth scaffolding disabled.",
        {
            "de": "Auth-Scaffold aus",
            "es": "Autenticación generada desactivada",
            "fr": "Authentification créée désactivée",
            "ja": "認証スキャフォールド オフ",
            "ko": "인증 스캐폴딩 꺼짐",
            "pt-BR": "Autenticação gerada desativada",
            "zh-Hans": "认证脚手架关",
            "zh-Hant": "驗證鷹架關",
        },
    ),
    "Environments on": simple(
        "Advanced options summary: environments creation enabled.",
        {
            "de": "Umgebungen an",
            "es": "Entornos activados",
            "fr": "Environnements activés",
            "ja": "環境 オン",
            "ko": "환경 켜짐",
            "pt-BR": "Ambientes ativados",
            "zh-Hans": "环境开",
            "zh-Hant": "環境開",
        },
    ),
    "Environments off": simple(
        "Advanced options summary: environments creation disabled.",
        {
            "de": "Umgebungen aus",
            "es": "Entornos desactivados",
            "fr": "Environnements désactivés",
            "ja": "環境 オフ",
            "ko": "환경 꺼짐",
            "pt-BR": "Ambientes desativados",
            "zh-Hans": "环境关",
            "zh-Hant": "環境關",
        },
    ),

    # Validation / service errors
    "Enter a valid HTTPS URL.": simple(
        "Validation error when spec import URL is invalid.",
        {
            "de": "Geben Sie eine gültige HTTPS-URL ein.",
            "es": "Introduce una URL HTTPS válida.",
            "fr": "Saisissez une URL HTTPS valide.",
            "ja": "有効な HTTPS URL を入力してください。",
            "ko": "유효한 HTTPS URL을 입력하세요.",
            "pt-BR": "Insira uma URL HTTPS válida.",
            "zh-Hans": "请输入有效的 HTTPS URL。",
            "zh-Hant": "請輸入有效的 HTTPS URL。",
        },
    ),
    "Paste a spec to continue.": simple(
        "Validation error when paste source is empty.",
        {
            "de": "Fügen Sie eine Spec ein, um fortzufahren.",
            "es": "Pega una especificación para continuar.",
            "fr": "Collez une spécification pour continuer.",
            "ja": "続行するには仕様を貼り付けてください。",
            "ko": "계속하려면 사양을 붙여넣으세요.",
            "pt-BR": "Cole uma especificação para continuar.",
            "zh-Hans": "请粘贴规范以继续。",
            "zh-Hant": "請貼上規格以繼續。",
        },
    ),
    "Could not read pasted content.": simple(
        "Error when pasted spec content cannot be decoded as UTF-8.",
        {
            "de": "Eingefügter Inhalt konnte nicht gelesen werden.",
            "es": "No se pudo leer el contenido pegado.",
            "fr": "Impossible de lire le contenu collé.",
            "ja": "貼り付けた内容を読み取れませんでした。",
            "ko": "붙여넣은 내용을 읽을 수 없습니다.",
            "pt-BR": "Não foi possível ler o conteúdo colado.",
            "zh-Hans": "无法读取粘贴的内容。",
            "zh-Hant": "無法讀取貼上的內容。",
        },
    ),
    "Content exceeds the 5 MiB size limit.": simple(
        "Validation error when spec content exceeds max bytes.",
        {
            "de": "Inhalt überschreitet das Limit von 5 MiB.",
            "es": "El contenido supera el límite de 5 MiB.",
            "fr": "Le contenu dépasse la limite de 5 Mio.",
            "ja": "コンテンツが 5 MiB のサイズ制限を超えています。",
            "ko": "콘텐츠가 5MiB 크기 제한을 초과합니다.",
            "pt-BR": "O conteúdo excede o limite de 5 MiB.",
            "zh-Hans": "内容超过 5 MiB 大小限制。",
            "zh-Hant": "內容超過 5 MiB 大小限制。",
        },
    ),
    "Invalid Spec": simple(
        "Error title for invalid API specification.",
        {
            "de": "Ungültige Spec",
            "es": "Especificación no válida",
            "fr": "Spécification non valide",
            "ja": "無効な仕様",
            "ko": "잘못된 사양",
            "pt-BR": "Especificação inválida",
            "zh-Hans": "无效规范",
            "zh-Hant": "無效規格",
        },
    ),
    "Unsupported Format": simple(
        "Error title for unsupported spec format.",
        {
            "de": "Nicht unterstütztes Format",
            "es": "Formato no compatible",
            "fr": "Format non pris en charge",
            "ja": "非対応の形式",
            "ko": "지원되지 않는 형식",
            "pt-BR": "Formato não suportado",
            "zh-Hans": "不支持的格式",
            "zh-Hant": "不支援的格式",
        },
    ),
    "Parse Error": simple(
        "Error title when spec parsing fails.",
        {
            "de": "Analysefehler",
            "es": "Error de análisis",
            "fr": "Erreur d'analyse",
            "ja": "解析エラー",
            "ko": "파싱 오류",
            "pt-BR": "Erro de análise",
            "zh-Hans": "解析错误",
            "zh-Hant": "解析錯誤",
        },
    ),
    "Import Failed": simple(
        "Error title for unknown spec import failures.",
        {
            "de": "Import fehlgeschlagen",
            "es": "Error al importar",
            "fr": "Échec de l'importation",
            "ja": "インポートに失敗しました",
            "ko": "가져오기 실패",
            "pt-BR": "Falha na importação",
            "zh-Hans": "导入失败",
            "zh-Hant": "匯入失敗",
        },
    ),
    "No importable operations found in this spec.": simple(
        "Fatal preview error when spec has no HTTP operations.",
        {
            "de": "In dieser Spec wurden keine importierbaren Operationen gefunden.",
            "es": "No se encontraron operaciones importables en esta especificación.",
            "fr": "Aucune opération importable trouvée dans cette spécification.",
            "ja": "この仕様にインポート可能なオペレーションが見つかりませんでした。",
            "ko": "이 사양에서 가져올 수 있는 오퍼레이션을 찾지 못했습니다.",
            "pt-BR": "Nenhuma operação importável encontrada nesta especificação.",
            "zh-Hans": "此规范中未找到可导入的操作。",
            "zh-Hant": "此規格中未找到可匯入的操作。",
        },
    ),
    "Could not save spec file to disk.": simple(
        "Error when writing imported spec to Application Support fails.",
        {
            "de": "Spec-Datei konnte nicht auf der Festplatte gespeichert werden.",
            "es": "No se pudo guardar el archivo de especificación en el disco.",
            "fr": "Impossible d'enregistrer le fichier de spécification sur le disque.",
            "ja": "仕様ファイルをディスクに保存できませんでした。",
            "ko": "사양 파일을 디스크에 저장할 수 없습니다.",
            "pt-BR": "Não foi possível salvar o arquivo de especificação no disco.",
            "zh-Hans": "无法将规范文件保存到磁盘。",
            "zh-Hant": "無法將規格檔案儲存到磁碟。",
        },
    ),
    "No OpenAPI entry file found in the selected folder. Expected openapi.yaml, openapi.json, swagger.yaml, or one or more *.openapi.json files.": simple(
        "Error when a chosen folder has no recognizable OpenAPI entry files.",
        {
            "de": "Keine OpenAPI-Einstiegsdatei im ausgewählten Ordner gefunden. Erwartet werden openapi.yaml, openapi.json, swagger.yaml oder eine oder mehrere *.openapi.json-Dateien.",
            "es": "No se encontró un archivo de entrada OpenAPI en la carpeta seleccionada. Se esperaba openapi.yaml, openapi.json, swagger.yaml o uno o más archivos *.openapi.json.",
            "fr": "Aucun fichier d'entrée OpenAPI trouvé dans le dossier sélectionné. Attendu : openapi.yaml, openapi.json, swagger.yaml ou un ou plusieurs fichiers *.openapi.json.",
            "ja": "選択したフォルダに OpenAPI のエントリファイルが見つかりません。openapi.yaml、openapi.json、swagger.yaml、または 1 つ以上の *.openapi.json を想定しています。",
            "ko": "선택한 폴더에서 OpenAPI 진입 파일을 찾지 못했습니다. openapi.yaml, openapi.json, swagger.yaml 또는 하나 이상의 *.openapi.json 파일이 필요합니다.",
            "pt-BR": "Nenhum arquivo de entrada OpenAPI encontrado na pasta selecionada. Esperado openapi.yaml, openapi.json, swagger.yaml ou um ou mais arquivos *.openapi.json.",
            "zh-Hans": "所选文件夹中未找到 OpenAPI 入口文件。需要 openapi.yaml、openapi.json、swagger.yaml 或一个或多个 *.openapi.json 文件。",
            "zh-Hant": "所選資料夾中未找到 OpenAPI 入口檔案。需要 openapi.yaml、openapi.json、swagger.yaml 或一個或多個 *.openapi.json 檔案。",
        },
    ),
    "Each spec becomes its own project.": simple(
        "Batch folder import note: one project is created per OpenAPI file.",
        {
            "de": "Jede Spec wird ein eigenes Projekt.",
            "es": "Cada especificación se convierte en su propio proyecto.",
            "fr": "Chaque spécification devient son propre projet.",
            "ja": "各仕様は個別のプロジェクトになります。",
            "ko": "각 사양은 별도의 프로젝트가 됩니다.",
            "pt-BR": "Cada especificação vira um projeto próprio.",
            "zh-Hans": "每个规范都会成为独立项目。",
            "zh-Hant": "每份規格都會成為獨立專案。",
        },
    ),
    "All specs import into one project.": simple(
        "Batch folder import note when grouping multiple specs into one project.",
        {
            "de": "Alle Specs werden in ein Projekt importiert.",
            "es": "Todas las especificaciones se importan en un solo proyecto.",
            "fr": "Toutes les spécifications sont importées dans un seul projet.",
            "ja": "すべての仕様を 1 つのプロジェクトにインポートします。",
            "ko": "모든 사양을 하나의 프로젝트로 가져옵니다.",
            "pt-BR": "Todas as especificações são importadas em um único projeto.",
            "zh-Hans": "所有规范将导入到同一个项目。",
            "zh-Hant": "所有規格將匯入到同一個專案。",
        },
    ),
    "Group specs in one project": simple(
        "Toggle label for grouping multiple folder specs into one project.",
        {
            "de": "Specs in einem Projekt gruppieren",
            "es": "Agrupar especificaciones en un proyecto",
            "fr": "Regrouper les spécifications dans un projet",
            "ja": "仕様を 1 つのプロジェクトにまとめる",
            "ko": "사양을 하나의 프로젝트로 묶기",
            "pt-BR": "Agrupar especificações em um projeto",
            "zh-Hans": "将规范归入同一项目",
            "zh-Hant": "將規格歸入同一專案",
        },
    ),
    "Creating one project with folders and requests.": simple(
        "Import progress subtitle when grouping multiple folder specs.",
        {
            "de": "Ein Projekt mit Ordnern und Requests wird erstellt.",
            "es": "Creando un proyecto con carpetas y solicitudes.",
            "fr": "Création d'un projet avec dossiers et requêtes.",
            "ja": "1 つのプロジェクトにフォルダとリクエストを作成しています。",
            "ko": "하나의 프로젝트에 폴더와 요청을 만드는 중입니다.",
            "pt-BR": "Criando um projeto com pastas e requisições.",
            "zh-Hans": "正在创建一个项目并添加文件夹和请求。",
            "zh-Hant": "正在建立一個專案並加入資料夾和請求。",
        },
    ),
    "Environment name": simple(
        "Label for grouped folder import environment name field.",
        {
            "de": "Umgebungsname",
            "es": "Nombre del entorno",
            "fr": "Nom de l'environnement",
            "ja": "環境名",
            "ko": "환경 이름",
            "pt-BR": "Nome do ambiente",
            "zh-Hans": "环境名称",
            "zh-Hant": "環境名稱",
        },
    ),
    "Base URLs": simple(
        "Section title for per-spec base URL variables in grouped folder import.",
        {
            "de": "Basis-URLs",
            "es": "URL base",
            "fr": "URL de base",
            "ja": "ベース URL",
            "ko": "기본 URL",
            "pt-BR": "URLs base",
            "zh-Hans": "基础 URL",
            "zh-Hant": "基礎 URL",
        },
    ),
    "Variable": simple(
        "Column label for editable environment variable name in grouped import.",
        {
            "de": "Variable",
            "es": "Variable",
            "fr": "Variable",
            "ja": "変数",
            "ko": "변수",
            "pt-BR": "Variável",
            "zh-Hans": "变量",
            "zh-Hant": "變數",
        },
    ),
    "Variable name": simple(
        "Placeholder for editable environment variable name.",
        {
            "de": "Variablenname",
            "es": "Nombre de variable",
            "fr": "Nom de variable",
            "ja": "変数名",
            "ko": "변수 이름",
            "pt-BR": "Nome da variável",
            "zh-Hans": "变量名",
            "zh-Hant": "變數名稱",
        },
    ),
    "URL": simple(
        "Read-only base URL preview label in grouped import.",
        {
            "de": "URL",
            "es": "URL",
            "fr": "URL",
            "ja": "URL",
            "ko": "URL",
            "pt-BR": "URL",
            "zh-Hans": "URL",
            "zh-Hant": "URL",
        },
    ),
    "Enter an environment name.": simple(
        "Validation error when grouped import environment name is empty.",
        {
            "de": "Geben Sie einen Umgebungsnamen ein.",
            "es": "Introduce un nombre de entorno.",
            "fr": "Saisissez un nom d'environnement.",
            "ja": "環境名を入力してください。",
            "ko": "환경 이름을 입력하세요.",
            "pt-BR": "Informe um nome de ambiente.",
            "zh-Hans": "请输入环境名称。",
            "zh-Hant": "請輸入環境名稱。",
        },
    ),
    "Specs (%lld)": simple(
        "Batch import preview section title when specs are grouped into one project.",
        {
            "de": "Specs (%lld)",
            "es": "Especificaciones (%lld)",
            "fr": "Spécifications (%lld)",
            "ja": "仕様（%lld）",
            "ko": "사양(%lld)",
            "pt-BR": "Especificações (%lld)",
            "zh-Hans": "规范（%lld）",
            "zh-Hant": "規格（%lld）",
        },
    ),
    "Supported formats: OpenAPI (YAML, YML, JSON), Postman Collection (JSON). Choose a folder for multi-file OpenAPI bundles with local $ref files, or a folder with multiple independent *.openapi.json specs.": simple(
        "File import tab helper text for single files and folder import modes.",
        {
            "de": "Unterstützte Formate: OpenAPI (YAML, YML, JSON), Postman Collection (JSON). Wählen Sie einen Ordner für mehrteilige OpenAPI-Bundles mit lokalen $ref-Dateien oder einen Ordner mit mehreren unabhängigen *.openapi.json-Specs.",
            "es": "Formatos compatibles: OpenAPI (YAML, YML, JSON), colección Postman (JSON). Elija una carpeta para bundles OpenAPI multiparte con archivos $ref locales, o una carpeta con varias especificaciones *.openapi.json independientes.",
            "fr": "Formats pris en charge : OpenAPI (YAML, YML, JSON), collection Postman (JSON). Choisissez un dossier pour des bundles OpenAPI multi-fichiers avec des $ref locaux, ou un dossier contenant plusieurs spécifications *.openapi.json indépendantes.",
            "ja": "対応形式：OpenAPI（YAML、YML、JSON）、Postman Collection（JSON）。ローカル $ref を含む複数ファイル OpenAPI バンドル用のフォルダ、または複数の独立した *.openapi.json 仕様があるフォルダを選択してください。",
            "ko": "지원 형식: OpenAPI(YAML, YML, JSON), Postman Collection(JSON). 로컬 $ref가 있는 다중 파일 OpenAPI 번들 폴더 또는 여러 개의 독립 *.openapi.json 사양이 있는 폴더를 선택하세요.",
            "pt-BR": "Formatos suportados: OpenAPI (YAML, YML, JSON), coleção Postman (JSON). Escolha uma pasta para bundles OpenAPI com $ref locais ou uma pasta com várias especificações *.openapi.json independentes.",
            "zh-Hans": "支持的格式：OpenAPI（YAML、YML、JSON）、Postman Collection（JSON）。可选择包含本地 $ref 的多文件 OpenAPI 包文件夹，或包含多个独立 *.openapi.json 规范的文件夹。",
            "zh-Hant": "支援的格式：OpenAPI（YAML、YML、JSON）、Postman Collection（JSON）。可選擇含本機 $ref 的多檔 OpenAPI 套件資料夾，或含多個獨立 *.openapi.json 規格的資料夾。",
        },
    ),
}
# fmt: on


def main() -> None:
    with XCSTRINGS.open(encoding="utf-8") as f:
        catalog = json.load(f)

    strings = catalog["strings"]
    added = []
    skipped = []

    for key, entry in STRINGS.items():
        if key in strings:
            skipped.append(key)
            continue
        strings[key] = entry
        added.append(key)

    catalog["strings"] = strings
    write_catalog(catalog)

    print(f"Added {len(added)} strings")
    if skipped:
        print(f"Skipped {len(skipped)} existing: {', '.join(skipped)}")


if __name__ == "__main__":
    main()
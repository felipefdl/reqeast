#!/usr/bin/env python3
"""Merge gRPC UI strings into Localizable.xcstrings (T23)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS = ROOT / "Reqeast" / "Localizable.xcstrings"

LOCALES = ("de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans", "zh-Hant")

GRPC = "gRPC"


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def simple(comment: str, translations: dict[str, str]) -> dict:
    return {
        "comment": comment,
        "localizations": {locale: unit(translations[locale]) for locale in LOCALES},
    }


def write_catalog(catalog: dict) -> None:
    """Write xcstrings using Xcode-style spacing (`"key" :`)."""
    text = json.dumps(catalog, ensure_ascii=False, indent=2)
    text = text.replace('": ', '" : ')
    XCSTRINGS.write_text(text + "\n", encoding="utf-8")


def merge_entry(existing: dict, new_entry: dict) -> tuple[dict, int]:
    """Add missing locales and comment; never overwrite existing localizations."""
    merged = 0
    if new_entry.get("comment") and not existing.get("comment"):
        existing["comment"] = new_entry["comment"]
    existing_locs = existing.setdefault("localizations", {})
    for locale, loc_entry in new_entry.get("localizations", {}).items():
        if locale not in existing_locs:
            existing_locs[locale] = loc_entry
            merged += 1
    return existing, merged


FIXUPS: dict[tuple[str, str], str] = {
    ("Discover from server", "ko"): "서버에서 서비스 검색",
    ("Half-close", "ja"): "ハーフクローズ",
    ("Half-close", "ko"): "하프 클로즈",
    ("Stream half-closed", "ja"): "ストリーム半クローズ",
    ("Stream half-closed", "ko"): "스트림 하프 클로즈",
    (
        "Proto descriptors are unavailable on this device. gRPC requests are read-only until the bundle can be downloaded from iCloud.",
        "pt-BR",
    ): "Descritores proto indisponíveis neste dispositivo. Requisições gRPC ficam somente leitura até o pacote ser baixado do iCloud.",
    (
        "Import .proto files to compile descriptors for gRPC requests.",
        "ko",
    ): ".proto 파일을 가져와 gRPC 요청용 디스크립터를 컴파일하세요.",
    ("Tap Send to invoke the RPC", "fr"): "Appuyez sur Envoyer pour appeler le RPC",
    ("Call gRPC services with protobuf messages over HTTP/2", "ja"): "HTTP/2 上で protobuf メッセージを使い gRPC サービスを呼び出す",
}


# fmt: off
STRINGS: dict[str, dict] = {
    # Protocol name — always untranslated
    "gRPC": simple(
        "Protocol name shown in pickers and badges.",
        {locale: GRPC for locale in LOCALES},
    ),

    # Protocol picker
    "Call gRPC services with protobuf messages over HTTP/2": simple(
        "Description for the gRPC protocol card in the new-request picker.",
        {
            "de": "gRPC-Dienste mit Protobuf-Nachrichten über HTTP/2 aufrufen",
            "es": "Llamar a servicios gRPC con mensajes protobuf sobre HTTP/2",
            "fr": "Appeler des services gRPC avec des messages protobuf sur HTTP/2",
            "ja": "HTTP/2 上で protobuf メッセージを使い gRPC サービスを呼び出す",
            "ko": "HTTP/2로 protobuf 메시지를 사용해 gRPC 서비스 호출",
            "pt-BR": "Chamar serviços gRPC com mensagens protobuf sobre HTTP/2",
            "zh-Hans": "通过 HTTP/2 使用 protobuf 消息调用 gRPC 服务",
            "zh-Hant": "透過 HTTP/2 使用 protobuf 訊息呼叫 gRPC 服務",
        },
    ),

    # Conversation log (streaming)
    "No gRPC Messages": simple(
        "Empty-state title when a gRPC streaming session has no messages.",
        {
            "de": "Keine gRPC-Nachrichten",
            "es": "Sin mensajes gRPC",
            "fr": "Aucun message gRPC",
            "ja": "gRPC メッセージなし",
            "ko": "gRPC 메시지 없음",
            "pt-BR": "Sem mensagens gRPC",
            "zh-Hans": "无 gRPC 消息",
            "zh-Hant": "無 gRPC 訊息",
        },
    ),
    "Send a request to start receiving stream responses": simple(
        "Empty-state description for server-streaming gRPC RPCs.",
        {
            "de": "Sende eine Anfrage, um Stream-Antworten zu empfangen",
            "es": "Envía una solicitud para empezar a recibir respuestas del stream",
            "fr": "Envoyez une requête pour commencer à recevoir les réponses du flux",
            "ja": "リクエストを送信してストリーム応答の受信を開始",
            "ko": "요청을 보내 스트림 응답 수신을 시작하세요",
            "pt-BR": "Envie uma requisição para começar a receber respostas do stream",
            "zh-Hans": "发送请求以开始接收流式响应",
            "zh-Hant": "傳送請求以開始接收串流回應",
        },
    ),
    "Connect to start sending stream messages": simple(
        "Empty-state description for client-streaming and bidi gRPC RPCs.",
        {
            "de": "Verbinde dich, um Stream-Nachrichten zu senden",
            "es": "Conéctate para empezar a enviar mensajes del stream",
            "fr": "Connectez-vous pour commencer à envoyer des messages du flux",
            "ja": "接続してストリームメッセージの送信を開始",
            "ko": "연결하여 스트림 메시지 전송을 시작하세요",
            "pt-BR": "Conecte-se para começar a enviar mensagens do stream",
            "zh-Hans": "连接后开始发送流式消息",
            "zh-Hant": "連線後開始傳送串流訊息",
        },
    ),

    # Schema panel
    "Discover services before sending.": simple(
        "Banner when server reflection descriptors are not yet loaded.",
        {
            "de": "Dienste ermitteln, bevor du sendest.",
            "es": "Descubre servicios antes de enviar.",
            "fr": "Découvrez les services avant d'envoyer.",
            "ja": "送信前にサービスを検出してください。",
            "ko": "전송하기 전에 서비스를 검색하세요.",
            "pt-BR": "Descubra serviços antes de enviar.",
            "zh-Hans": "发送前请先发现服务。",
            "zh-Hant": "傳送前請先探索服務。",
        },
    ),
    "Schema": simple(
        "Section title for proto bundle vs server reflection source.",
        {
            "de": "Schema",
            "es": "Esquema",
            "fr": "Schéma",
            "ja": "スキーマ",
            "ko": "스키마",
            "pt-BR": "Esquema",
            "zh-Hans": "架构",
            "zh-Hant": "架構",
        },
    ),
    "Schema source": simple(
        "Picker label for choosing proto bundle or server reflection.",
        {
            "de": "Schemaquelle",
            "es": "Fuente del esquema",
            "fr": "Source du schéma",
            "ja": "スキーマソース",
            "ko": "스키마 소스",
            "pt-BR": "Fonte do esquema",
            "zh-Hans": "架构来源",
            "zh-Hant": "架構來源",
        },
    ),
    "Proto bundle": simple(
        "Schema source option: project proto bundle.",
        {
            "de": "Proto-Bundle",
            "es": "Paquete proto",
            "fr": "Bundle proto",
            "ja": "Proto バンドル",
            "ko": "Proto 번들",
            "pt-BR": "Pacote proto",
            "zh-Hans": "Proto 包",
            "zh-Hant": "Proto 套件",
        },
    ),
    "Server reflection": simple(
        "Schema source option: gRPC server reflection.",
        {
            "de": "Server Reflection",
            "es": "Reflexión del servidor",
            "fr": "Réflexion serveur",
            "ja": "サーバーリフレクション",
            "ko": "서버 리플렉션",
            "pt-BR": "Reflexão do servidor",
            "zh-Hans": "服务器反射",
            "zh-Hant": "伺服器反射",
        },
    ),
    "No proto bundles in this project.": simple(
        "Caption when the project has no imported proto bundles.",
        {
            "de": "Keine Proto-Bundles in diesem Projekt.",
            "es": "No hay paquetes proto en este proyecto.",
            "fr": "Aucun bundle proto dans ce projet.",
            "ja": "このプロジェクトに Proto バンドルはありません。",
            "ko": "이 프로젝트에 Proto 번들이 없습니다.",
            "pt-BR": "Nenhum pacote proto neste projeto.",
            "zh-Hans": "此项目中没有 Proto 包。",
            "zh-Hant": "此專案中沒有 Proto 套件。",
        },
    ),
    "Active bundle": simple(
        "Picker label for the selected proto bundle.",
        {
            "de": "Aktives Bundle",
            "es": "Paquete activo",
            "fr": "Bundle actif",
            "ja": "有効なバンドル",
            "ko": "활성 번들",
            "pt-BR": "Pacote ativo",
            "zh-Hans": "当前包",
            "zh-Hant": "目前套件",
        },
    ),
    "Select a bundle": simple(
        "Placeholder when no proto bundle is selected.",
        {
            "de": "Bundle auswählen",
            "es": "Seleccionar paquete",
            "fr": "Sélectionner un bundle",
            "ja": "バンドルを選択",
            "ko": "번들 선택",
            "pt-BR": "Selecionar pacote",
            "zh-Hans": "选择包",
            "zh-Hant": "選擇套件",
        },
    ),
    "Manage Proto Library": simple(
        "Button to open the proto bundle library sheet.",
        {
            "de": "Proto-Bibliothek verwalten",
            "es": "Administrar biblioteca proto",
            "fr": "Gérer la bibliothèque proto",
            "ja": "Proto ライブラリを管理",
            "ko": "Proto 라이브러리 관리",
            "pt-BR": "Gerenciar biblioteca proto",
            "zh-Hans": "管理 Proto 库",
            "zh-Hant": "管理 Proto 程式庫",
        },
    ),
    "Discovering…": simple(
        "Button label while fetching services via server reflection.",
        {
            "de": "Ermittle…",
            "es": "Descubriendo…",
            "fr": "Découverte…",
            "ja": "検出中…",
            "ko": "검색 중…",
            "pt-BR": "Descobrindo…",
            "zh-Hans": "正在发现…",
            "zh-Hant": "正在探索…",
        },
    ),
    "Discover from server": simple(
        "Button to discover gRPC services via server reflection.",
        {
            "de": "Vom Server ermitteln",
            "es": "Descubrir desde el servidor",
            "fr": "Découvrir depuis le serveur",
            "ja": "サーバーから検出",
            "ko": "서버에서 검색",
            "pt-BR": "Descobrir no servidor",
            "zh-Hans": "从服务器发现",
            "zh-Hant": "從伺服器探索",
        },
    ),
    "Save descriptors": simple(
        "Button to save reflection descriptors as a proto bundle.",
        {
            "de": "Deskriptoren speichern",
            "es": "Guardar descriptores",
            "fr": "Enregistrer les descripteurs",
            "ja": "ディスクリプタを保存",
            "ko": "디스크립터 저장",
            "pt-BR": "Salvar descritores",
            "zh-Hans": "保存描述符",
            "zh-Hant": "儲存描述符",
        },
    ),
    "Save reflection descriptors as a project proto bundle": simple(
        "Help text when reflection descriptors can be saved.",
        {
            "de": "Reflection-Deskriptoren als Projekt-Proto-Bundle speichern",
            "es": "Guardar descriptores de reflexión como paquete proto del proyecto",
            "fr": "Enregistrer les descripteurs de réflexion comme bundle proto du projet",
            "ja": "リフレクションディスクリプタをプロジェクトの Proto バンドルとして保存",
            "ko": "리플렉션 디스크립터를 프로젝트 Proto 번들로 저장",
            "pt-BR": "Salvar descritores de reflexão como pacote proto do projeto",
            "zh-Hans": "将反射描述符保存为项目 Proto 包",
            "zh-Hant": "將反射描述符儲存為專案 Proto 套件",
        },
    ),
    "Discover services before saving descriptors.": simple(
        "Help text when save-descriptors is disabled.",
        {
            "de": "Dienste ermitteln, bevor Deskriptoren gespeichert werden.",
            "es": "Descubre servicios antes de guardar descriptores.",
            "fr": "Découvrez les services avant d'enregistrer les descripteurs.",
            "ja": "ディスクリプタを保存する前にサービスを検出してください。",
            "ko": "디스크립터를 저장하기 전에 서비스를 검색하세요.",
            "pt-BR": "Descubra serviços antes de salvar descritores.",
            "zh-Hans": "保存描述符前请先发现服务。",
            "zh-Hant": "儲存描述符前請先探索服務。",
        },
    ),
    "Save Descriptors": simple(
        "Sheet title for naming a reflection-derived proto bundle.",
        {
            "de": "Deskriptoren speichern",
            "es": "Guardar descriptores",
            "fr": "Enregistrer les descripteurs",
            "ja": "ディスクリプタを保存",
            "ko": "디스크립터 저장",
            "pt-BR": "Salvar descritores",
            "zh-Hans": "保存描述符",
            "zh-Hant": "儲存描述符",
        },
    ),
    "Create a proto bundle from the current reflection descriptors.": simple(
        "Sheet description when saving reflection descriptors.",
        {
            "de": "Proto-Bundle aus den aktuellen Reflection-Deskriptoren erstellen.",
            "es": "Crear un paquete proto a partir de los descriptores de reflexión actuales.",
            "fr": "Créer un bundle proto à partir des descripteurs de réflexion actuels.",
            "ja": "現在のリフレクションディスクリプタから Proto バンドルを作成します。",
            "ko": "현재 리플렉션 디스크립터에서 Proto 번들을 만듭니다.",
            "pt-BR": "Criar um pacote proto a partir dos descritores de reflexão atuais.",
            "zh-Hans": "根据当前反射描述符创建 Proto 包。",
            "zh-Hant": "根據目前的反射描述符建立 Proto 套件。",
        },
    ),
    "Bundle name": simple(
        "Text field label for naming a proto bundle.",
        {
            "de": "Bundle-Name",
            "es": "Nombre del paquete",
            "fr": "Nom du bundle",
            "ja": "バンドル名",
            "ko": "번들 이름",
            "pt-BR": "Nome do pacote",
            "zh-Hans": "包名称",
            "zh-Hant": "套件名稱",
        },
    ),

    # Method picker
    "RPC": simple(
        "Section label for gRPC service and method fields.",
        {
            "de": "RPC",
            "es": "RPC",
            "fr": "RPC",
            "ja": "RPC",
            "ko": "RPC",
            "pt-BR": "RPC",
            "zh-Hans": "RPC",
            "zh-Hant": "RPC",
        },
    ),
    "Select service": simple(
        "Picker placeholder when no gRPC service is selected.",
        {
            "de": "Dienst auswählen",
            "es": "Seleccionar servicio",
            "fr": "Sélectionner un service",
            "ja": "サービスを選択",
            "ko": "서비스 선택",
            "pt-BR": "Selecionar serviço",
            "zh-Hans": "选择服务",
            "zh-Hant": "選擇服務",
        },
    ),
    "Select method": simple(
        "Picker placeholder when no gRPC method is selected.",
        {
            "de": "Methode auswählen",
            "es": "Seleccionar método",
            "fr": "Sélectionner une méthode",
            "ja": "メソッドを選択",
            "ko": "메서드 선택",
            "pt-BR": "Selecionar método",
            "zh-Hans": "选择方法",
            "zh-Hant": "選擇方法",
        },
    ),

    # Body editor
    "Request Body": simple(
        "Section title for the gRPC request message editor.",
        {
            "de": "Anfrageinhalt",
            "es": "Cuerpo de la solicitud",
            "fr": "Corps de la requête",
            "ja": "リクエスト本文",
            "ko": "요청 본문",
            "pt-BR": "Corpo da requisição",
            "zh-Hans": "请求正文",
            "zh-Hant": "請求內文",
        },
    ),
    "Body mode": simple(
        "Picker label for JSON vs hex request body editing.",
        {
            "de": "Inhaltsmodus",
            "es": "Modo del cuerpo",
            "fr": "Mode du corps",
            "ja": "本文モード",
            "ko": "본문 모드",
            "pt-BR": "Modo do corpo",
            "zh-Hans": "正文模式",
            "zh-Hant": "內文模式",
        },
    ),
    "Hex": simple(
        "Body display mode: hexadecimal bytes.",
        {
            "de": "Hex",
            "es": "Hex",
            "fr": "Hex",
            "ja": "Hex",
            "ko": "Hex",
            "pt-BR": "Hex",
            "zh-Hans": "Hex",
            "zh-Hant": "Hex",
        },
    ),
    "Half-close": simple(
        "Streaming control: gRPC half-close.",
        {
            "de": "Halbschließen",
            "es": "Semi-cierre",
            "fr": "Demi-fermeture",
            "ja": "ハーフクローズ",
            "ko": "하프 클로즈",
            "pt-BR": "Meio-fechamento",
            "zh-Hans": "半关闭",
            "zh-Hant": "半關閉",
        },
    ),

    # Read-only banner
    "Proto descriptors are unavailable on this device. gRPC requests are read-only until the bundle can be downloaded from iCloud.": simple(
        "Banner when a proto bundle is not yet hydrated from iCloud.",
        {
            "de": "Proto-Deskriptoren sind auf diesem Gerät nicht verfügbar. gRPC-Anfragen sind schreibgeschützt, bis das Bundle aus iCloud geladen wurde.",
            "es": "Los descriptores proto no están disponibles en este dispositivo. Las solicitudes gRPC son de solo lectura hasta que el paquete se descargue de iCloud.",
            "fr": "Les descripteurs proto ne sont pas disponibles sur cet appareil. Les requêtes gRPC sont en lecture seule jusqu'au téléchargement du bundle depuis iCloud.",
            "ja": "このデバイスでは Proto ディスクリプタを利用できません。iCloud からバンドルをダウンロードするまで gRPC リクエストは読み取り専用です。",
            "ko": "이 기기에서 Proto 디스크립터를 사용할 수 없습니다. iCloud에서 번들을 다운로드할 때까지 gRPC 요청은 읽기 전용입니다.",
            "pt-BR": "Descritores proto indisponíveis neste dispositivo. Requisições gRPC ficam somente leitura até o pacote ser baixado do iCloud.",
            "zh-Hans": "此设备上的 Proto 描述符不可用。在从 iCloud 下载包之前，gRPC 请求为只读。",
            "zh-Hant": "此裝置上的 Proto 描述符無法使用。在從 iCloud 下載套件前，gRPC 請求為唯讀。",
        },
    ),

    # Proto library sheet
    "Proto Library": simple(
        "Title for the proto bundle management sheet.",
        {
            "de": "Proto-Bibliothek",
            "es": "Biblioteca proto",
            "fr": "Bibliothèque proto",
            "ja": "Proto ライブラリ",
            "ko": "Proto 라이브러리",
            "pt-BR": "Biblioteca proto",
            "zh-Hans": "Proto 库",
            "zh-Hant": "Proto 程式庫",
        },
    ),
    "No Proto Bundles": simple(
        "Empty-state title in the proto library sheet.",
        {
            "de": "Keine Proto-Bundles",
            "es": "Sin paquetes proto",
            "fr": "Aucun bundle proto",
            "ja": "Proto バンドルなし",
            "ko": "Proto 번들 없음",
            "pt-BR": "Sem pacotes proto",
            "zh-Hans": "无 Proto 包",
            "zh-Hant": "無 Proto 套件",
        },
    ),
    "Import .proto files to compile descriptors for gRPC requests.": simple(
        "Empty-state description in the proto library sheet.",
        {
            "de": "Importiere .proto-Dateien, um Deskriptoren für gRPC-Anfragen zu kompilieren.",
            "es": "Importa archivos .proto para compilar descriptores para solicitudes gRPC.",
            "fr": "Importez des fichiers .proto pour compiler des descripteurs pour les requêtes gRPC.",
            "ja": ".proto ファイルをインポートして gRPC リクエスト用のディスクリプタをコンパイルします。",
            "ko": ".proto 파일을 가져와 gRPC 요청용 디스크립터를 컴파일하세요.",
            "pt-BR": "Importe arquivos .proto para compilar descritores para requisições gRPC.",
            "zh-Hans": "导入 .proto 文件以编译 gRPC 请求所需的描述符。",
            "zh-Hant": "匯入 .proto 檔案以編譯 gRPC 請求所需的描述符。",
        },
    ),
    "Waiting for iCloud download": simple(
        "Status when a proto bundle asset is not yet available locally.",
        {
            "de": "Warte auf iCloud-Download",
            "es": "Esperando descarga de iCloud",
            "fr": "En attente du téléchargement iCloud",
            "ja": "iCloud のダウンロードを待機中",
            "ko": "iCloud 다운로드 대기 중",
            "pt-BR": "Aguardando download do iCloud",
            "zh-Hans": "等待从 iCloud 下载",
            "zh-Hant": "等待從 iCloud 下載",
        },
    ),
    "Entry file": simple(
        "Picker label for the proto bundle entry .proto file.",
        {
            "de": "Einstiegsdatei",
            "es": "Archivo de entrada",
            "fr": "Fichier d'entrée",
            "ja": "エントリファイル",
            "ko": "진입 파일",
            "pt-BR": "Arquivo de entrada",
            "zh-Hans": "入口文件",
            "zh-Hant": "進入檔案",
        },
    ),
    "Importing…": simple(
        "Button label while compiling and importing proto files.",
        {
            "de": "Importiere…",
            "es": "Importando…",
            "fr": "Importation…",
            "ja": "インポート中…",
            "ko": "가져오는 중…",
            "pt-BR": "Importando…",
            "zh-Hans": "正在导入…",
            "zh-Hant": "正在匯入…",
        },
    ),
    "Delete this proto bundle?": simple(
        "Confirmation dialog when deleting a proto bundle.",
        {
            "de": "Dieses Proto-Bundle löschen?",
            "es": "¿Eliminar este paquete proto?",
            "fr": "Supprimer ce bundle proto ?",
            "ja": "この Proto バンドルを削除しますか？",
            "ko": "이 Proto 번들을 삭제할까요?",
            "pt-BR": "Excluir este pacote proto?",
            "zh-Hans": "删除此 Proto 包？",
            "zh-Hant": "刪除此 Proto 套件？",
        },
    ),
    "Proto Bundle": simple(
        "Default name for a newly imported proto bundle.",
        {
            "de": "Proto-Bundle",
            "es": "Paquete proto",
            "fr": "Bundle proto",
            "ja": "Proto バンドル",
            "ko": "Proto 번들",
            "pt-BR": "Pacote proto",
            "zh-Hans": "Proto 包",
            "zh-Hant": "Proto 套件",
        },
    ),
    "Choose Proto Files": simple(
        "macOS open-panel title for selecting .proto files.",
        {
            "de": "Proto-Dateien auswählen",
            "es": "Elegir archivos proto",
            "fr": "Choisir des fichiers proto",
            "ja": "Proto ファイルを選択",
            "ko": "Proto 파일 선택",
            "pt-BR": "Escolher arquivos proto",
            "zh-Hans": "选择 Proto 文件",
            "zh-Hant": "選擇 Proto 檔案",
        },
    ),

    # Unary response log
    "Enter an authority above to get started": simple(
        "Empty-state hint when gRPC authority is empty.",
        {
            "de": "Gib oben eine Authority ein, um zu beginnen",
            "es": "Introduce una authority arriba para empezar",
            "fr": "Saisissez une authority ci-dessus pour commencer",
            "ja": "上に authority を入力して開始",
            "ko": "위에 authority를 입력하여 시작하세요",
            "pt-BR": "Insira uma authority acima para começar",
            "zh-Hans": "在上方输入 authority 以开始",
            "zh-Hant": "在上方輸入 authority 以開始",
        },
    ),
    "Tap Send to invoke the RPC": simple(
        "iOS empty-state hint for unary gRPC send.",
        {
            "de": "Tippe auf Senden, um den RPC aufzurufen",
            "es": "Pulsa Enviar para invocar el RPC",
            "fr": "Appuyez sur Envoyer pour appeler le RPC",
            "ja": "送信をタップして RPC を呼び出す",
            "ko": "보내기를 탭하여 RPC 호출",
            "pt-BR": "Toque em Enviar para invocar o RPC",
            "zh-Hans": "点按发送以调用 RPC",
            "zh-Hant": "點按傳送以呼叫 RPC",
        },
    ),
    "Display": simple(
        "Picker label for JSON vs hex response display.",
        {
            "de": "Anzeige",
            "es": "Visualización",
            "fr": "Affichage",
            "ja": "表示",
            "ko": "표시",
            "pt-BR": "Exibição",
            "zh-Hans": "显示",
            "zh-Hant": "顯示",
        },
    ),
    "Empty Response": simple(
        "Label when a unary gRPC response has no message body.",
        {
            "de": "Leere Antwort",
            "es": "Respuesta vacía",
            "fr": "Réponse vide",
            "ja": "空の応答",
            "ko": "빈 응답",
            "pt-BR": "Resposta vazia",
            "zh-Hans": "空响应",
            "zh-Hant": "空回應",
        },
    ),
    "Truncated": simple(
        "Badge when a gRPC response or stream message was truncated.",
        {
            "de": "Gekürzt",
            "es": "Truncado",
            "fr": "Tronqué",
            "ja": "切り詰め",
            "ko": "잘림",
            "pt-BR": "Truncado",
            "zh-Hans": "已截断",
            "zh-Hant": "已截斷",
        },
    ),
    "gRPC %lld": simple(
        "Unary response status bar prefix with gRPC status code.",
        {
            "de": "gRPC %lld",
            "es": "gRPC %lld",
            "fr": "gRPC %lld",
            "ja": "gRPC %lld",
            "ko": "gRPC %lld",
            "pt-BR": "gRPC %lld",
            "zh-Hans": "gRPC %lld",
            "zh-Hant": "gRPC %lld",
        },
    ),

    # Validation / config errors
    "Select a proto bundle before sending.": simple(
        "Error when proto bundle schema is selected but none is chosen.",
        {
            "de": "Wähle ein Proto-Bundle aus, bevor du sendest.",
            "es": "Selecciona un paquete proto antes de enviar.",
            "fr": "Sélectionnez un bundle proto avant d'envoyer.",
            "ja": "送信前に Proto バンドルを選択してください。",
            "ko": "전송하기 전에 Proto 번들을 선택하세요.",
            "pt-BR": "Selecione um pacote proto antes de enviar.",
            "zh-Hans": "发送前请选择 Proto 包。",
            "zh-Hant": "傳送前請選擇 Proto 套件。",
        },
    ),
    "Proto descriptors are unavailable on this device.": simple(
        "Error when proto bundle descriptors are missing locally.",
        {
            "de": "Proto-Deskriptoren sind auf diesem Gerät nicht verfügbar.",
            "es": "Los descriptores proto no están disponibles en este dispositivo.",
            "fr": "Les descripteurs proto ne sont pas disponibles sur cet appareil.",
            "ja": "このデバイスでは Proto ディスクリプタを利用できません。",
            "ko": "이 기기에서 Proto 디스크립터를 사용할 수 없습니다.",
            "pt-BR": "Descritores proto indisponíveis neste dispositivo.",
            "zh-Hans": "此设备上的 Proto 描述符不可用。",
            "zh-Hant": "此裝置上的 Proto 描述符無法使用。",
        },
    ),
    "Failed to load descriptor bytes for the selected bundle.": simple(
        "Error when descriptors.bin cannot be read from disk.",
        {
            "de": "Deskriptor-Bytes für das ausgewählte Bundle konnten nicht geladen werden.",
            "es": "No se pudieron cargar los bytes del descriptor del paquete seleccionado.",
            "fr": "Impossible de charger les octets du descripteur pour le bundle sélectionné.",
            "ja": "選択したバンドルのディスクリプタバイトを読み込めませんでした。",
            "ko": "선택한 번들의 디스크립터 바이트를 불러오지 못했습니다.",
            "pt-BR": "Falha ao carregar os bytes do descritor do pacote selecionado.",
            "zh-Hans": "无法加载所选包的描述符字节。",
            "zh-Hant": "無法載入所選套件的描述符位元組。",
        },
    ),
    "Hex body is empty.": simple(
        "Validation error when hex request body is blank.",
        {
            "de": "Hex-Inhalt ist leer.",
            "es": "El cuerpo hex está vacío.",
            "fr": "Le corps hex est vide.",
            "ja": "Hex 本文が空です。",
            "ko": "Hex 본문이 비어 있습니다.",
            "pt-BR": "O corpo hex está vazio.",
            "zh-Hans": "Hex 正文为空。",
            "zh-Hant": "Hex 內文為空。",
        },
    ),
    "gRPC Error": simple(
        "Error title for gRPC transport or status failures.",
        {
            "de": "gRPC-Fehler",
            "es": "Error gRPC",
            "fr": "Erreur gRPC",
            "ja": "gRPC エラー",
            "ko": "gRPC 오류",
            "pt-BR": "Erro gRPC",
            "zh-Hans": "gRPC 错误",
            "zh-Hant": "gRPC 錯誤",
        },
    ),

    # Session store (streaming log)
    "Metadata received": simple(
        "System message when gRPC response metadata arrives.",
        {
            "de": "Metadaten empfangen",
            "es": "Metadatos recibidos",
            "fr": "Métadonnées reçues",
            "ja": "メタデータを受信",
            "ko": "메타데이터 수신",
            "pt-BR": "Metadados recebidos",
            "zh-Hans": "已接收元数据",
            "zh-Hant": "已接收中繼資料",
        },
    ),
    "Metadata received: %@": simple(
        "System message with gRPC metadata header summary.",
        {
            "de": "Metadaten empfangen: %@",
            "es": "Metadatos recibidos: %@",
            "fr": "Métadonnées reçues : %@",
            "ja": "メタデータを受信: %@",
            "ko": "메타데이터 수신: %@",
            "pt-BR": "Metadados recebidos: %@",
            "zh-Hans": "已接收元数据：%@",
            "zh-Hant": "已接收中繼資料：%@",
        },
    ),
    "Stream half-closed": simple(
        "System message when the local gRPC stream is half-closed.",
        {
            "de": "Stream halbgeschlossen",
            "es": "Stream semi-cerrado",
            "fr": "Flux demi-fermé",
            "ja": "ストリーム半クローズ",
            "ko": "스트림 하프 클로즈",
            "pt-BR": "Stream meio-fechado",
            "zh-Hans": "流已半关闭",
            "zh-Hant": "串流已半關閉",
        },
    ),
    "Completed %@": simple(
        "System message when a gRPC stream completes with status.",
        {
            "de": "Abgeschlossen %@",
            "es": "Completado %@",
            "fr": "Terminé %@",
            "ja": "完了 %@",
            "ko": "완료 %@",
            "pt-BR": "Concluído %@",
            "zh-Hans": "已完成 %@",
            "zh-Hant": "已完成 %@",
        },
    ),
    "Half-close failed: %@": simple(
        "System message when gRPC half-close fails.",
        {
            "de": "Halbschließen fehlgeschlagen: %@",
            "es": "Error en semi-cierre: %@",
            "fr": "Échec de la demi-fermeture : %@",
            "ja": "ハーフクローズに失敗: %@",
            "ko": "하프 클로즈 실패: %@",
            "pt-BR": "Falha no meio-fechamento: %@",
            "zh-Hans": "半关闭失败：%@",
            "zh-Hant": "半關閉失敗：%@",
        },
    ),

    # Shortcuts intent
    "Send gRPC Request": simple(
        "Title for the Send gRPC Request App Intent and shortcut.",
        {
            "de": "gRPC-Anfrage senden",
            "es": "Enviar solicitud gRPC",
            "fr": "Envoyer une requête gRPC",
            "ja": "gRPC リクエストを送信",
            "ko": "gRPC 요청 보내기",
            "pt-BR": "Enviar requisição gRPC",
            "zh-Hans": "发送 gRPC 请求",
            "zh-Hant": "傳送 gRPC 請求",
        },
    ),
    "Invoke a unary gRPC RPC from Reqeast and return the response JSON.": simple(
        "Description for the Send gRPC Request App Intent.",
        {
            "de": "Einen unären gRPC-RPC von Reqeast ausführen und die Antwort-JSON zurückgeben.",
            "es": "Invocar un RPC gRPC unario desde Reqeast y devolver el JSON de respuesta.",
            "fr": "Appeler un RPC gRPC unaire depuis Reqeast et renvoyer le JSON de réponse.",
            "ja": "Reqeast からユニタリ gRPC RPC を呼び出し、応答 JSON を返します。",
            "ko": "Reqeast에서 단일 gRPC RPC를 호출하고 응답 JSON을 반환합니다.",
            "pt-BR": "Invocar um RPC gRPC unário no Reqeast e retornar o JSON da resposta.",
            "zh-Hans": "从 Reqeast 调用一元 gRPC RPC 并返回响应 JSON。",
            "zh-Hant": "從 Reqeast 呼叫一元 gRPC RPC 並傳回回應 JSON。",
        },
    ),
    "Choose a gRPC request": simple(
        "Disambiguation dialog when resolving a gRPC request for Shortcuts.",
        {
            "de": "Wähle eine gRPC-Anfrage",
            "es": "Elige una solicitud gRPC",
            "fr": "Choisissez une requête gRPC",
            "ja": "gRPC リクエストを選択",
            "ko": "gRPC 요청 선택",
            "pt-BR": "Escolha uma requisição gRPC",
            "zh-Hans": "选择 gRPC 请求",
            "zh-Hant": "選擇 gRPC 請求",
        },
    ),
}
# fmt: on


def main() -> None:
    catalog = json.loads(XCSTRINGS.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})

    merged_locales = 0
    new_keys = 0

    for key, entry in STRINGS.items():
        if key in strings:
            strings[key], n = merge_entry(strings[key], entry)
            merged_locales += n
        else:
            strings[key] = entry
            merged_locales += len(entry.get("localizations", {}))
            new_keys += 1

    fixups_applied = 0
    for (key, locale), value in FIXUPS.items():
        if key not in strings:
            continue
        strings[key].setdefault("localizations", {})[locale] = unit(value)
        fixups_applied += 1

    write_catalog(catalog)
    print(
        f"Merged {merged_locales} locale entries across {len(STRINGS)} keys "
        f"({new_keys} new keys, {fixups_applied} fixups)"
    )


if __name__ == "__main__":
    main()
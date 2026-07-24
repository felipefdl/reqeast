#!/usr/bin/env python3
"""Generate SpecImport project.json goldens from normalized.json fixtures."""

from __future__ import annotations

import hashlib
import json
import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "ReqeastTests/Fixtures/SpecImport"

FOLDER_STRATEGY = {
    "petstore-2.0": "tags",
    "petstore-3.0": "tags",
    "petstore-3.1": "tags",
    "stripe-like": "tags",
    "servers-multi": "tags",
    "auth-schemes": "tags",
    "folder-tags": "tags",
    "folder-paths": "paths",
    "folder-flat": "flat",
    "postman-nested": "tags",
    "postman-vars": "tags",
    "har-capture": "tags",
    "graphql-simple": "tags",
    "asyncapi-http": "tags",
}


def deterministic_uuid(name: str) -> str:
    digest = hashlib.sha256(name.encode()).digest()[:16]
    b = bytearray(digest)
    b[6] = (b[6] & 0x0F) | 0x40
    b[8] = (b[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(b)))


def project_id(fixture: str) -> str:
    return deterministic_uuid(f"spec-import-project:{fixture}")


def entity_id(fixture: str, kind: str, name: str) -> str:
    return deterministic_uuid(f"{fixture}:{kind}:{name}")


def static_path_prefix(path: str) -> str:
    segments: list[str] = []
    for segment in path.split("/"):
        if not segment:
            continue
        if segment.startswith("{") and segment.endswith("}"):
            continue
        segments.append(segment)
    return "/".join(segments)


def templated_url(path: str) -> str:
    return "{{base_url}}" + re.sub(r"\{([^}]+)\}", r"{{\1}}", path)


def map_auth(auth: dict | None) -> dict:
    if not auth:
        return {
            "authType": "none",
            "authToken": "",
            "authUsername": "",
            "authPassword": "",
            "authApiKeyName": "",
            "authApiKeyValue": "",
            "authApiKeyLocation": "header",
            "authOAuth2GrantType": "",
            "authOAuth2AuthURL": "",
            "authOAuth2TokenURL": "",
            "authOAuth2Scopes": "",
        }

    scheme = auth["scheme_type"]
    placeholder = auth["placeholder_value"]
    if scheme == "apiKey":
        location = "header" if auth.get("header_name") else "query"
        return {
            "authType": "apiKey",
            "authToken": "",
            "authUsername": "",
            "authPassword": "",
            "authApiKeyName": auth.get("header_name") or auth.get("query_name") or "",
            "authApiKeyValue": placeholder,
            "authApiKeyLocation": location,
            "authOAuth2GrantType": "",
            "authOAuth2AuthURL": "",
            "authOAuth2TokenURL": "",
            "authOAuth2Scopes": "",
        }
    if scheme in {"http:Bearer", "openIdConnect", "oauth2"}:
        token = placeholder.removeprefix("Bearer ")
        auth_type = "oauth2" if scheme == "oauth2" else "bearer"
        result = {
            "authType": auth_type,
            "authToken": token,
            "authUsername": "",
            "authPassword": "",
            "authApiKeyName": "",
            "authApiKeyValue": "",
            "authApiKeyLocation": "header",
            "authOAuth2GrantType": "",
            "authOAuth2AuthURL": "",
            "authOAuth2TokenURL": "",
            "authOAuth2Scopes": "",
        }
        if scheme == "oauth2":
            result["authOAuth2GrantType"] = auth.get("oauth2_grant_type") or "clientCredentials"
            result["authOAuth2AuthURL"] = auth.get("oauth2_auth_url") or ""
            result["authOAuth2TokenURL"] = auth.get("oauth2_token_url") or ""
            result["authOAuth2Scopes"] = auth.get("oauth2_scopes") or ""
        return result
    if scheme == "http:Basic":
        stripped = placeholder.removeprefix("Basic ")
        if ":" in stripped:
            user, password = stripped.split(":", 1)
        else:
            user, password = "{{username}}", "{{password}}"
        return {
            "authType": "basic",
            "authToken": "",
            "authUsername": user,
            "authPassword": password,
            "authApiKeyName": "",
            "authApiKeyValue": "",
            "authApiKeyLocation": "header",
            "authOAuth2GrantType": "",
            "authOAuth2AuthURL": "",
            "authOAuth2TokenURL": "",
            "authOAuth2Scopes": "",
        }
    return {
        "authType": "bearer",
        "authToken": placeholder,
        "authUsername": "",
        "authPassword": "",
        "authApiKeyName": "",
        "authApiKeyValue": "",
        "authApiKeyLocation": "header",
        "authOAuth2GrantType": "",
        "authOAuth2AuthURL": "",
        "authOAuth2TokenURL": "",
        "authOAuth2Scopes": "",
    }


def is_graphql_operation(operation: dict) -> bool:
    return "graphql" in operation.get("tags", [])


def graphql_variable_value(raw: str):
    if raw in {"true", "false"}:
        return raw == "true"
    if raw == "null":
        return None
    if raw.isdigit() or (raw.startswith("-") and raw[1:].isdigit()):
        return int(raw)
    if raw.startswith("[") or raw.startswith("{"):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            pass
    return raw


def sync_graphql_variables(body_content: str, params: list[dict]) -> str:
    if not params:
        return body_content
    try:
        payload = json.loads(body_content)
    except json.JSONDecodeError:
        return body_content
    payload["variables"] = {
        entry["key"]: graphql_variable_value(entry["value"])
        for entry in params
        if entry["enabled"]
    }
    # Match Swift JSONSerialization.prettyPrinted spacing (`"key" : value`).
    return json.dumps(payload, indent=2, sort_keys=True).replace('":', '" :')


def map_body(body: dict) -> dict:
    kind = body["kind"]
    if kind == "None":
        return {"bodyType": "none", "bodyContent": "", "bodyFormData": [], "bodyFormDataEntries": [], "rawContentType": "text", "binaryFileName": ""}
    if kind == "Json":
        return {"bodyType": "json", "bodyContent": body["content"], "bodyFormData": [], "bodyFormDataEntries": [], "rawContentType": "text", "binaryFileName": ""}
    if kind == "Urlencoded":
        fields = [{"key": f["key"], "value": f["value"], "enabled": f["enabled"]} for f in body["fields"]]
        return {"bodyType": "urlencoded", "bodyContent": "", "bodyFormData": fields, "bodyFormDataEntries": [], "rawContentType": "text", "binaryFileName": ""}
    if kind == "FormData":
        entries = []
        for entry in body["entries"]:
            entries.append({
                "key": entry["key"],
                "value": entry["value"],
                "enabled": True,
                "fieldType": "file" if entry["is_file"] else "text",
                "fileName": entry.get("file_name") or "",
                "mimeType": entry.get("content_type") or "",
            })
        return {"bodyType": "formData", "bodyContent": "", "bodyFormData": [], "bodyFormDataEntries": entries, "rawContentType": "text", "binaryFileName": ""}
    if kind == "Raw":
        return {"bodyType": "raw", "bodyContent": body["content"], "bodyFormData": [], "bodyFormDataEntries": [], "rawContentType": "text", "binaryFileName": ""}
    if kind == "Binary":
        return {"bodyType": "binary", "bodyContent": "", "bodyFormData": [], "bodyFormDataEntries": [], "rawContentType": "text", "binaryFileName": body["file_name"]}
    raise ValueError(f"unknown body kind {kind}")


def build_folder_plan(project: dict, strategy: str, fixture_name: str) -> tuple[list[dict], dict[str, str]]:
    if strategy == "flat":
        return [], {}
    if strategy == "tags":
        folders = [
            {
                "id": entity_id(fixture_name, "folder", folder["id"]),
                "name": folder["name"],
                "key": folder["id"],
            }
            for folder in sorted(project["folders"], key=lambda f: f["sort_hint"])
        ]
        op_keys = {
            op["primary_key"]: op["folder_id"]
            for op in project["operations"]
            if op.get("folder_id")
        }
        return folders, op_keys

    folder_entries: dict[str, dict] = {}
    op_keys: dict[str, str] = {}
    for index, op in enumerate(project["operations"]):
        static_path = static_path_prefix(op["path"])
        if not static_path:
            continue
        key = f"path:{static_path}"
        if key not in folder_entries:
            folder_entries[key] = {
                "id": entity_id(fixture_name, "folder", key),
                "name": static_path,
                "key": key,
                "sort_hint": index,
            }
        op_keys[op["primary_key"]] = key
    folders = sorted(folder_entries.values(), key=lambda f: f["sort_hint"])
    return folders, op_keys


def map_fixture(name: str) -> dict:
    normalized_path = FIXTURES / f"{name}.normalized.json"
    payload = json.loads(normalized_path.read_text())
    project = payload["project"]
    strategy = FOLDER_STRATEGY[name]
    pid = project_id(name)

    folders, op_folder_keys = build_folder_plan(project, strategy, name)
    golden_folders = [{"id": f["id"], "name": f["name"]} for f in folders]
    folder_id_by_key = {f["key"]: f["id"] for f in folders}

    requests = []
    for index, op in enumerate(project["operations"]):
        params = []
        headers = []
        for param in op["parameters"]:
            entry = {"key": param["name"], "value": param["value"], "enabled": param["enabled"]}
            location = param["location"]
            if location == "Query":
                params.append(entry)
            elif location == "Header":
                headers.append(entry)

        body = map_body(op["body"])
        auth = map_auth(op.get("auth"))
        folder_id = None
        if op["primary_key"] in op_folder_keys:
            folder_id = folder_id_by_key[op_folder_keys[op["primary_key"]]]

        if is_graphql_operation(op):
            headers = [{"key": "Content-Type", "value": "application/json", "enabled": True}]
            if body["bodyType"] == "json":
                body["bodyContent"] = sync_graphql_variables(body["bodyContent"], params)
            http = {
                "method": "POST",
                "url": "{{base_url}}",
                "params": params,
                "headers": headers,
                **body,
                **auth,
            }
        else:
            http = {
                "method": op["method"],
                "url": templated_url(op["path"]),
                "params": params,
                "headers": headers,
                **body,
                **auth,
            }

        requests.append({
            "id": entity_id(name, "request", op["primary_key"]),
            "name": op["name"],
            "folderId": folder_id,
            "sortOrder": index,
            "specIdentity": {
                "primaryKey": op["primary_key"],
                "alternateKeys": op["alternate_keys"],
            },
            "http": http,
        })

    environments = []
    for index, env in enumerate(project["environments"]):
        environments.append({
            "id": entity_id(name, "environment", env["name"]),
            "name": env["name"],
            "isActive": index == 0,
            "variables": [
                {"key": v["key"], "value": v["value"], "enabled": v["enabled"]}
                for v in env["variables"]
            ],
        })

    return {
        "project": {"id": pid, "name": project["title"]},
        "folders": golden_folders,
        "requests": requests,
        "environments": environments,
    }


def main() -> None:
    for name in FOLDER_STRATEGY:
        golden = map_fixture(name)
        out = FIXTURES / f"{name}.project.json"
        out.write_text(json.dumps(golden, indent=2, sort_keys=True) + "\n")
        print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
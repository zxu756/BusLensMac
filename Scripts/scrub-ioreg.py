#!/usr/bin/env python3
"""Deterministic, read-only scrubber for raw macOS ioreg and system_profiler captures.

Removes hardware serial numbers, UUIDs/UIDs, ContainerIDs, MAC/BT addresses, DROM blobs,
console usernames, user paths, user-client process strings, and HID report descriptors
while preserving USB and Thunderbolt link-speed and topology properties.
Never adds synthetic entries.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import re
import sys
from typing import Any

SCRIPT_REL_PATH = "Scripts/scrub-ioreg.py"

EXACT_REMOVED_KEYS: frozenset[str] = frozenset(
    {
        "Address",
        "BTAddress",
        "ComputerName",
        "ContainerID",
        "DROM",
        "Device GUID",
        "DeviceAddress",
        "DiskImageURL",
        "Domain UUID",
        "Elements",
        "HPM Address",
        "HostName",
        "IOConsoleUsers",
        "IOMACAddress",
        "IOPlatformSerialNumber",
        "IOPlatformUUID",
        "IOUserClientCreator",
        "IOUserServerCDHash",
        "IOUserServerName",
        "InstanceID",
        "LocalHostName",
        "MAC Address",
        "MLB",
        "Micro Address",
        "PCI Path",
        "Path",
        "ReportDescriptor",
        "SerialNumber",
        "Switch UID",
        "TRM Hash Set",
        "TRM Transport ID",
        "UID",
        "USB Address",
        "USB Serial Number",
        "USBDeviceKeySerialNumber",
        "UUID",
        "UsbDeviceSignature",
        "UsbExclusiveOwner",
        "UserPreferences",
        "bluetooth-dev-addr",
        "die-id",
        "domain_uuid_key",
        "iSerialNumber",
        "kCGSSessionUserNameKey",
        "kOSBundleDextUniqueIdentifier",
        "kUSBAddress",
        "kUSBContainerID",
        "kUSBSerialNumberString",
        "serial_num",
        "sessionID",
        "switch_uid_key",
        "uid_key",
        "unique-chip-id",
    }
)

SENSITIVE_KEY_SUBSTRINGS: tuple[str, ...] = (
    "serial",
    "uuid",
    "containerid",
    "guid",
    "macaddress",
    "mac-address",
    "bd_addr",
    "unique-id",
)

UUID_EXACT_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
UUID_INLINE_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)
USER_PATH_RE = re.compile(r"/(?:Users|private/var/folders)/[^\s\"'<>]+")
IOREG_PROP_LINE_RE = re.compile(r'^([\s|]*)"((?:\\.|[^"\\])*)"(\s*=\s*)(.*)$')
INLINE_DICT_ENTRY_RE = re.compile(r'^(\s*)"((?:\\.|[^"\\])*)"(\s*=\s*)(.*)$', re.DOTALL)
EXISTING_PLIST_REMOVED_RE = re.compile(r"^\s*Removed Keys:\s*(.+?)\s*$", re.MULTILINE)


def should_remove_key(key: str) -> bool:
    if key in EXACT_REMOVED_KEYS:
        return True
    if UUID_EXACT_RE.match(key):
        return True
    lower = key.lower()
    if any(tok in lower for tok in SENSITIVE_KEY_SUBSTRINGS):
        return True
    if lower == "uid" or lower.endswith("_uid") or lower.endswith(" uid") or lower.endswith("uid_key"):
        return True
    return False


def scrub_string_value(val: str) -> str:
    val = USER_PATH_RE.sub("<redacted-path>", val)
    val = UUID_INLINE_RE.sub("<redacted-uuid>", val)
    return val


def parse_removed_keys_csv(raw_csv: str) -> set[str]:
    if not raw_csv or raw_csv.strip() == "(none present in input)":
        return set()
    return {part.strip() for part in raw_csv.split(",") if part.strip()}


def scrub_plist_node(node: Any, removed_keys: set[str]) -> Any:
    if isinstance(node, dict):
        out: dict[str, Any] = {}
        for k, v in node.items():
            key_str = str(k)
            if should_remove_key(key_str):
                removed_keys.add("<uuid-dict-key>" if UUID_EXACT_RE.match(key_str) else key_str)
                continue
            out[key_str] = scrub_plist_node(v, removed_keys)
        return out
    if isinstance(node, list):
        return [scrub_plist_node(item, removed_keys) for item in node]
    if isinstance(node, str):
        return scrub_string_value(node)
    return node


def format_xml_plist_with_header(
    payload: Any,
    command: str,
    captured_at: str,
    removed_keys: set[str],
) -> bytes:
    raw_xml = plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True).decode("utf-8")
    removed_str = ", ".join(sorted(removed_keys)) if removed_keys else "(none present in input)"
    safe_cmd = command.replace("--", "- -")
    safe_removed = removed_str.replace("--", "- -")
    comment_block = (
        "<!--\n"
        "  Scrubbed IORegistry Capture (Read-Only)\n"
        f"  Scrub Script: {SCRIPT_REL_PATH}\n"
        f"  Captured At (UTC): {captured_at}\n"
        f"  Original Command: {safe_cmd}\n"
        f"  Removed Keys: {safe_removed}\n"
        "  Synthetic Entries Added: 0\n"
        "-->\n"
    )
    xml_decl = '<?xml version="1.0" encoding="UTF-8"?>\n'
    if raw_xml.startswith(xml_decl):
        raw_xml = xml_decl + comment_block + raw_xml[len(xml_decl) :]
    else:
        raw_xml = comment_block + raw_xml
    return raw_xml.encode("utf-8")


def split_balanced_top_level(inner: str, sep: str = ",") -> list[str]:
    parts: list[str] = []
    cur_start = 0
    i = 0
    n = len(inner)
    brace_depth = 0
    paren_depth = 0
    in_angle = False
    in_quote = False
    while i < n:
        ch = inner[i]
        if in_quote:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == '"':
                in_quote = False
            i += 1
            continue
        if in_angle:
            if ch == '"':
                in_quote = True
            elif ch == ">":
                in_angle = False
            i += 1
            continue
        if ch == '"':
            in_quote = True
        elif ch == "<":
            in_angle = True
        elif ch == "{":
            brace_depth += 1
        elif ch == "}":
            brace_depth = max(0, brace_depth - 1)
        elif ch == "(":
            paren_depth += 1
        elif ch == ")":
            paren_depth = max(0, paren_depth - 1)
        elif ch == sep and brace_depth == 0 and paren_depth == 0:
            parts.append(inner[cur_start:i])
            cur_start = i + 1
        i += 1
    parts.append(inner[cur_start:])
    return parts


def scrub_ioreg_inline_value(raw_val: str, removed_keys: set[str]) -> str:
    stripped = raw_val.strip()
    if len(stripped) >= 2 and stripped[0] == "{" and stripped[-1] == "}":
        inner = stripped[1:-1]
        if not inner.strip():
            return raw_val
        entries = split_balanced_top_level(inner, ",")
        kept_entries: list[str] = []
        parsed_all = True
        for entry in entries:
            if not entry.strip():
                continue
            m = INLINE_DICT_ENTRY_RE.match(entry)
            if not m:
                parsed_all = False
                break
            lead_ws, raw_sub_key, eq_sep, sub_val = m.groups()
            sub_key = raw_sub_key.replace('\\"', '"').replace("\\\\", "\\")
            if should_remove_key(sub_key):
                removed_keys.add("<uuid-dict-key>" if UUID_EXACT_RE.match(sub_key) else sub_key)
                continue
            scrubbed_sub_val = scrub_ioreg_inline_value(sub_val, removed_keys)
            kept_entries.append(f'{lead_ws}"{raw_sub_key}"{eq_sep}{scrubbed_sub_val}')
        if parsed_all:
            lead = raw_val[: len(raw_val) - len(raw_val.lstrip())]
            trail = raw_val[len(raw_val.rstrip()) :]
            return f"{lead}{{" + ",".join(kept_entries) + f"}}{trail}"
    elif len(stripped) >= 2 and stripped[0] == "(" and stripped[-1] == ")":
        inner = stripped[1:-1]
        if not inner.strip():
            return raw_val
        elems = split_balanced_top_level(inner, ",")
        scrubbed_elems = [scrub_ioreg_inline_value(el, removed_keys) for el in elems]
        lead = raw_val[: len(raw_val) - len(raw_val.lstrip())]
        trail = raw_val[len(raw_val.rstrip()) :]
        return f"{lead}(" + ",".join(scrubbed_elems) + f"){trail}"
    return scrub_string_value(raw_val)


def scrub_ioreg_text(
    raw_text: str,
    command: str,
    captured_at: str,
    extra_removed_keys: set[str],
) -> bytes:
    removed_keys: set[str] = set(extra_removed_keys)
    kept_lines: list[str] = []
    header_prefixes = (
        "# Scrubbed IORegistry Text Capture",
        "# Scrub Script:",
        "# Captured At (UTC):",
        "# Original Command:",
        "# Removed Keys:",
        "# Synthetic Lines Added:",
    )
    for line in raw_text.splitlines():
        if line.startswith("# Removed Keys:"):
            removed_keys.update(parse_removed_keys_csv(line.split(":", 1)[1]))
            continue
        if line.startswith(header_prefixes):
            continue
        match = IOREG_PROP_LINE_RE.match(line)
        if match:
            indent, raw_prop_key, eq_sep, rhs = match.groups()
            prop_key = raw_prop_key.replace('\\"', '"').replace("\\\\", "\\")
            if should_remove_key(prop_key):
                removed_keys.add("<uuid-dict-key>" if UUID_EXACT_RE.match(prop_key) else prop_key)
                continue
            scrubbed_rhs = scrub_ioreg_inline_value(rhs, removed_keys)
            kept_lines.append(f'{indent}"{raw_prop_key}"{eq_sep}{scrubbed_rhs}')
            continue
        kept_lines.append(scrub_string_value(line))

    removed_str = ", ".join(sorted(removed_keys)) if removed_keys else "(none present in input)"
    header_lines = [
        "# Scrubbed IORegistry Text Capture (Read-Only)",
        f"# Scrub Script: {SCRIPT_REL_PATH}",
        f"# Captured At (UTC): {captured_at}",
        f"# Original Command: {command}",
        f"# Removed Keys: {removed_str}",
        "# Synthetic Lines Added: 0",
    ]
    body = "\n".join(header_lines + kept_lines) + "\n"
    return body.encode("utf-8")


def scrub_json_node(node: Any, removed_keys: set[str]) -> Any:
    if isinstance(node, dict):
        out: dict[str, Any] = {}
        for k in sorted(node.keys()):
            if k == "_capture_metadata":
                continue
            if should_remove_key(k):
                removed_keys.add(k)
                continue
            out[k] = scrub_json_node(node[k], removed_keys)
        return out
    if isinstance(node, list):
        return [scrub_json_node(item, removed_keys) for item in node]
    if isinstance(node, str):
        return scrub_string_value(node)
    return node


def scrub_sp_json(
    raw_bytes: bytes,
    command: str,
    captured_at: str,
    extra_removed_keys: set[str],
) -> bytes:
    parsed = json.loads(raw_bytes.decode("utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError("Expected top-level JSON object for system_profiler output")
    existing_meta = parsed.get("_capture_metadata") if isinstance(parsed.get("_capture_metadata"), dict) else {}
    removed_keys: set[str] = set(extra_removed_keys)
    if isinstance(existing_meta.get("removed_keys"), list):
        removed_keys.update(str(x) for x in existing_meta["removed_keys"])
    scrubbed_body = scrub_json_node(parsed, removed_keys)

    final_obj: dict[str, Any] = {
        "_capture_metadata": {
            "captured_at_utc": captured_at,
            "command": command,
            "removed_keys": sorted(removed_keys),
            "scrub_script": SCRIPT_REL_PATH,
            "synthetic_entries_added": 0,
        }
    }
    for k in sorted(scrubbed_body.keys()):
        final_obj[k] = scrubbed_body[k]
    return (json.dumps(final_obj, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def detect_format(raw_bytes: bytes) -> str:
    stripped = raw_bytes.lstrip()
    if stripped.startswith(b"<?xml") or stripped.startswith(b"<!DOCTYPE plist") or stripped.startswith(b"<plist"):
        return "plist"
    if stripped.startswith(b"{"):
        return "sp-json"
    return "ioreg-text"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Deterministic scrubber for raw ioreg (XML plist or -l text) and system_profiler JSON."
    )
    parser.add_argument("--input", help="Single raw capture file (reads stdin when omitted unless --usb-input/--tb-input set).")
    parser.add_argument("--usb-input", help="Raw XML plist from `/usr/sbin/ioreg -a -r -c AppleUSBHostPort -l`.")
    parser.add_argument("--tb-input", help="Raw XML plist from `/usr/sbin/ioreg -a -r -c IOThunderboltSwitch -l`.")
    parser.add_argument("--output", help="Destination path for scrubbed output (writes stdout when omitted).")
    parser.add_argument(
        "--format",
        choices=["auto", "plist", "ioreg-text", "sp-json"],
        default="auto",
        help="Input format (defaults to auto-detection).",
    )
    parser.add_argument(
        "--command",
        default="/usr/sbin/ioreg -l -w0",
        help="Original capture command(s) recorded in the scrubbed file header.",
    )
    parser.add_argument(
        "--captured-at",
        default=None,
        help="Capture UTC timestamp in ISO-8601 format (defaults to current UTC time).",
    )
    parser.add_argument(
        "--declare-removed-keys",
        default="",
        help="Optional comma-separated keys already removed prior to re-normalization.",
    )
    args = parser.parse_args()

    captured_at = args.captured_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    extra_removed = parse_removed_keys_csv(args.declare_removed_keys)

    if args.usb_input or args.tb_input:
        if args.input:
            parser.error("--input cannot be combined with --usb-input / --tb-input")
        removed_keys: set[str] = set(extra_removed)
        combined: dict[str, Any] = {}
        if args.usb_input:
            usb_raw = plistlib.loads(Path(args.usb_input).read_bytes())
            combined["AppleUSBHostPort"] = scrub_plist_node(usb_raw, removed_keys)
        if args.tb_input:
            tb_raw = plistlib.loads(Path(args.tb_input).read_bytes())
            combined["IOThunderboltSwitch"] = scrub_plist_node(tb_raw, removed_keys)
        default_cmd = (
            "/usr/sbin/ioreg -a -r -c AppleUSBHostPort -l ; /usr/sbin/ioreg -a -r -c IOThunderboltSwitch -l"
            if args.command == "/usr/sbin/ioreg -l -w0"
            else args.command
        )
        out_bytes = format_xml_plist_with_header(combined, default_cmd, captured_at, removed_keys)
    else:
        raw_bytes = Path(args.input).read_bytes() if args.input else sys.stdin.buffer.read()
        fmt = detect_format(raw_bytes) if args.format == "auto" else args.format
        if fmt == "plist":
            removed_keys = set(extra_removed)
            head_text = raw_bytes[:4096].decode("utf-8", errors="ignore")
            existing_match = EXISTING_PLIST_REMOVED_RE.search(head_text)
            if existing_match:
                removed_keys.update(parse_removed_keys_csv(existing_match.group(1)))
            loaded = plistlib.loads(raw_bytes)
            scrubbed = scrub_plist_node(loaded, removed_keys)
            out_bytes = format_xml_plist_with_header(scrubbed, args.command, captured_at, removed_keys)
        elif fmt == "sp-json":
            out_bytes = scrub_sp_json(raw_bytes, args.command, captured_at, extra_removed)
        else:
            out_bytes = scrub_ioreg_text(
                raw_bytes.decode("utf-8", errors="replace"),
                args.command,
                captured_at,
                extra_removed,
            )

    if args.output:
        Path(args.output).write_bytes(out_bytes)
    else:
        sys.stdout.buffer.write(out_bytes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

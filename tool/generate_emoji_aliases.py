from __future__ import annotations

import json
import re
import tempfile
import urllib.request
import unicodedata
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UNICODE_VERSION = "17.0"
UNICODE_SOURCE_URL = (
    f"https://www.unicode.org/Public/{UNICODE_VERSION}.0/emoji/emoji-test.txt"
)
GEMOJI_COMMIT = "0eca75db9301421efc8710baf7a7576793ae452a"
GEMOJI_SOURCE_URL = (
    "https://raw.githubusercontent.com/github/gemoji/"
    f"{GEMOJI_COMMIT}/db/emoji.json"
)
UNICODE_SOURCE = (
    Path(tempfile.gettempdir()) / f"shuyo-emoji-test-{UNICODE_VERSION}.txt"
)
GEMOJI_SOURCE = Path(tempfile.gettempdir()) / f"gemoji-{GEMOJI_COMMIT}.json"
OUTPUT = ROOT / "lib" / "data" / "services" / "emoji_aliases.dart"


def key_for_name(name: str) -> str:
    normalized = unicodedata.normalize("NFKD", name)
    ascii_name = normalized.encode("ascii", "ignore").decode("ascii")
    ascii_name = ascii_name.replace("&", " and ")
    return re.sub(
        r"_+",
        "_",
        re.sub(r"[^a-zA-Z0-9+\-]+", "_", ascii_name.lower()),
    ).strip("_")


def dart_value(codepoints: list[int]) -> str:
    return "".join(f"\\u{{{codepoint:X}}}" for codepoint in codepoints)


def add_alias(
    aliases: dict[str, str],
    key: str,
    value: str,
    *,
    reject_conflict: bool = False,
) -> None:
    if not key:
        return
    existing = aliases.get(key)
    if existing is None:
        aliases[key] = value
        return
    if existing != value and reject_conflict:
        raise ValueError(f"Conflicting emoji alias {key!r}: {existing!r} != {value!r}")


def spelling_variants(key: str) -> set[str]:
    variants = {key}
    if "-" in key:
        variants.add(key.replace("-", "_"))
    replacements = [
        ("savor", "savour"),
        ("savory", "savoury"),
        ("gray", "grey"),
        ("mustache", "moustache"),
    ]
    for left, right in replacements:
        for value in list(variants):
            if left in value:
                variants.add(value.replace(left, right))
            if right in value:
                variants.add(value.replace(right, left))
            if "-" in value:
                variants.add(value.replace("-", "_"))
    return variants


def simplified_variants(key: str) -> set[str]:
    variants = set()
    replacements = [
        ("face_savouring_delicious_food", "face_savouring_food"),
        ("face_savoring_delicious_food", "face_savoring_food"),
        ("white_smiling_face", "smiling_face"),
        ("black_heart_suit", "heart_suit"),
        ("black_spade_suit", "spade_suit"),
        ("black_diamond_suit", "diamond_suit"),
        ("black_club_suit", "club_suit"),
    ]
    for source, target in replacements:
        if key == source:
            variants.add(target)
    return variants


def unicode_name_aliases(codepoints: list[int]) -> set[str]:
    filtered = [
        codepoint
        for codepoint in codepoints
        if codepoint not in {0xFE0E, 0xFE0F, 0x200D}
        and not (0x1F3FB <= codepoint <= 0x1F3FF)
        and not (0xE0020 <= codepoint <= 0xE007F)
    ]
    if len(filtered) != 1:
        return set()
    try:
        key = key_for_name(unicodedata.name(chr(filtered[0])))
    except ValueError:
        return set()
    variants = set()
    for spelling in spelling_variants(key):
        variants.add(spelling)
        variants.update(simplified_variants(spelling))
    return variants


def regional_flag_alias(codepoints: list[int]) -> str | None:
    if len(codepoints) != 2:
        return None
    if not all(0x1F1E6 <= codepoint <= 0x1F1FF for codepoint in codepoints):
        return None
    return "".join(chr(ord("a") + codepoint - 0x1F1E6) for codepoint in codepoints)


def parse_emoji_test() -> dict[str, str]:
    if not UNICODE_SOURCE.exists():
        urllib.request.urlretrieve(UNICODE_SOURCE_URL, UNICODE_SOURCE)

    aliases: dict[str, str] = {}
    line_pattern = re.compile(
        r"^([0-9A-F ]+)\s*;\s*(fully-qualified|component)\s*#\s*\S+\s+E[0-9.]+\s+(.+)$"
    )
    for line in UNICODE_SOURCE.read_text(encoding="utf-8").splitlines():
        match = line_pattern.match(line)
        if match is None:
            continue
        codepoints = [int(part, 16) for part in match.group(1).split()]
        value = dart_value(codepoints)
        cldr_key = key_for_name(match.group(3))
        for key in spelling_variants(cldr_key):
            add_alias(aliases, key, value)
        if cldr_key.startswith("flag_"):
            add_alias(aliases, cldr_key.removeprefix("flag_"), value)
        for key in unicode_name_aliases(codepoints):
            add_alias(aliases, key, value)
        flag_key = regional_flag_alias(codepoints)
        if flag_key is not None:
            add_alias(aliases, flag_key, value)
    return aliases


def _without_presentation_and_tone(codepoints: list[int]) -> tuple[int, ...]:
    return tuple(
        codepoint
        for codepoint in codepoints
        if codepoint != 0xFE0F and not (0x1F3FB <= codepoint <= 0x1F3FF)
    )


def _tone_sequences() -> dict[tuple[tuple[int, ...], int], str]:
    sequences = {}
    line_pattern = re.compile(
        r"^([0-9A-F ]+)\s*;\s*fully-qualified\s*#"
    )
    for line in UNICODE_SOURCE.read_text(encoding="utf-8").splitlines():
        match = line_pattern.match(line)
        if match is None:
            continue
        codepoints = [int(part, 16) for part in match.group(1).split()]
        tones = [
            codepoint for codepoint in codepoints if 0x1F3FB <= codepoint <= 0x1F3FF
        ]
        if len(tones) != 1:
            continue
        tone = tones[0] - 0x1F3F9
        key = (_without_presentation_and_tone(codepoints), tone)
        sequences[key] = dart_value(codepoints)
    return sequences


def parse_gemoji_data() -> dict[str, str]:
    if not GEMOJI_SOURCE.exists():
        urllib.request.urlretrieve(GEMOJI_SOURCE_URL, GEMOJI_SOURCE)

    data = json.loads(GEMOJI_SOURCE.read_text(encoding="utf-8"))
    tone_sequences = _tone_sequences()
    aliases: dict[str, str] = {}
    for entry in data:
        emoji = entry.get("emoji")
        shortcodes = entry.get("aliases")
        if not isinstance(emoji, str) or not isinstance(shortcodes, list):
            continue
        codepoints = [ord(character) for character in emoji]
        value = dart_value(codepoints)
        for shortcode in shortcodes:
            if not isinstance(shortcode, str):
                continue
            add_alias(aliases, shortcode, value, reject_conflict=True)
            if entry.get("skin_tones") is True:
                base = _without_presentation_and_tone(codepoints)
                for tone in range(2, 7):
                    tone_value = tone_sequences.get((base, tone))
                    if tone_value is not None:
                        add_alias(
                            aliases,
                            f"{shortcode}:t{tone}",
                            tone_value,
                            reject_conflict=True,
                        )
    return aliases


def merge_aliases(unicode_aliases: dict[str, str], gemoji_aliases: dict[str, str]) -> dict[str, str]:
    merged = dict(unicode_aliases)
    # Common shortcode aliases should win over colliding Unicode name/code
    # aliases, for example :tm: is the trademark sign rather than flag: TM.
    merged.update(gemoji_aliases)
    return merged


def write_dart(aliases: dict[str, str]) -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "// Generated from Unicode emoji-test.txt and GitHub gemoji data.",
        f"// Unicode source: {UNICODE_SOURCE_URL}",
        f"// gemoji source commit: {GEMOJI_COMMIT}",
        "// Unicode terms: https://www.unicode.org/terms_of_use.html",
        "// gemoji license: MIT (see THIRD_PARTY_NOTICES.md)",
        "// Do not edit entries manually; update the generator/source data instead.",
        "",
        "const emojiUnicodeAliases = <String, String>{",
    ]
    for key, value in sorted(aliases.items()):
        lines.append(f"  '{key}': '{value}',")
    lines.extend(["};", ""])
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    unicode_aliases = parse_emoji_test()
    aliases = merge_aliases(
        unicode_aliases,
        parse_gemoji_data(),
    )
    write_dart(aliases)
    print(f"Generated {len(aliases)} emoji aliases at {OUTPUT}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Insere um novo <item> logo após a abertura de <channel> em um appcast.xml do Sparkle."""
import sys

def main() -> None:
    appcast_path, item_xml = sys.argv[1], sys.argv[2]

    with open(appcast_path, encoding="utf-8") as f:
        content = f.read()

    marker = "<channel>"
    index = content.index(marker) + len(marker)
    updated = content[:index] + "\n" + item_xml.rstrip("\n") + content[index:]

    with open(appcast_path, "w", encoding="utf-8") as f:
        f.write(updated)


if __name__ == "__main__":
    main()

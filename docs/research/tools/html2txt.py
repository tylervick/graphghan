#!/usr/bin/env python3
"""Strip HTML to readable text with stdlib only. Usage: html2txt.py < page.html"""

import re
import sys
from html.parser import HTMLParser


class TextExtractor(HTMLParser):
    SKIP = {"script", "style", "noscript", "svg", "nav", "footer", "header", "form"}
    BLOCK = {
        "p",
        "div",
        "br",
        "li",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "tr",
        "section",
        "article",
        "ul",
        "ol",
        "table",
        "blockquote",
    }

    def __init__(self):
        super().__init__()
        self.out = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        if tag in self.BLOCK:
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        if tag in self.BLOCK:
            self.out.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.out.append(data)


def main():
    parser = TextExtractor()
    parser.feed(sys.stdin.buffer.read().decode("utf-8", errors="replace"))
    text = "".join(parser.out)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n\n", text)
    sys.stdout.write(text.strip() + "\n")


if __name__ == "__main__":
    main()

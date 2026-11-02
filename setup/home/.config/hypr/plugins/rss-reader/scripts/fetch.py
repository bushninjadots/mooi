#!/usr/bin/env python3
# RSS/Atom fetcher for the RSS Reader plugin (equisdots).
#
# Usage: fetch.py URL [URL ...]
#   Prints one JSON array of entries (newest first) on stdout. With no URLs it
#   falls back to $RSS_FEEDS_FILE, then to the legacy in-tree feeds.txt (the
#   pre-plugin location), and prints [] when nothing is configured.
import os
import json
import subprocess
import sys
import time
import re
import xml.etree.ElementTree as ET
from html import unescape

PER_FEED = 15
TOTAL = 60
CURL_TIMEOUT = 12
UA = "Mozilla/5.0 (X11; Linux x86_64) equisdots-rss-reader/0.2"


def clean_html(text):
    text = re.sub(r'<[^>]+>', '', text or '')
    return unescape(text).strip()


def parse_date(date_str):
    if not date_str:
        return 0
    try:
        from email.utils import parsedate_to_datetime
        return int(parsedate_to_datetime(date_str).timestamp())
    except Exception:
        pass
    try:
        import dateutil.parser
        return int(dateutil.parser.parse(date_str).timestamp())
    except Exception:
        pass
    return int(time.time())


def fetch_feed(url):
    try:
        result = subprocess.run(
            ['curl', '-s', '--max-time', str(CURL_TIMEOUT), '-L', '-A', UA, url],
            capture_output=True, text=True, timeout=CURL_TIMEOUT + 3,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return []
        return parse_feed_xml(result.stdout, url)
    except Exception:
        return []


def parse_feed_xml(xml_data, feed_url):
    entries = []
    try:
        root = ET.fromstring(xml_data)
    except ET.ParseError:
        return entries

    ns = {}
    for m in re.finditer(r'xmlns:?(\w*)=["\']([^"\']+)["\']', xml_data[:2000]):
        prefix, uri = m.groups()
        if prefix:
            ns[prefix] = uri

    # RSS 2.0
    channel = root.find('channel')
    feed_title = ''
    if channel is not None:
        ft = channel.find('title')
        if ft is not None:
            feed_title = clean_html(ft.text)
        for item in channel.findall('item'):
            title = link = desc = pub_date = ''
            for child in item:
                tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if tag == 'title' and not title:
                    title = clean_html(child.text)
                elif tag == 'link' and not link:
                    link = (child.text or '').strip()
                elif tag == 'description' and not desc:
                    desc = clean_html(child.text)
                elif tag == 'pubDate' and not pub_date:
                    pub_date = child.text or ''
            if title:
                entries.append({
                    'feed': feed_title or feed_url,
                    'title': title, 'link': link,
                    'desc': desc[:220],
                    'time': parse_date(pub_date),
                })

    # Atom
    if not entries:
        ft = root.find('title')
        if ft is not None:
            feed_title = clean_html(ft.text)
        for entry in root.findall('entry'):
            title = link = desc = updated = ''
            for child in entry:
                tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if tag == 'title' and not title:
                    title = clean_html(child.text)
                elif tag == 'link' and not link:
                    link = child.attrib.get('href', '')
                elif tag == 'summary' and not desc:
                    desc = clean_html(child.text)
                elif tag == 'content' and not desc:
                    desc = clean_html(child.text)
                elif tag == 'updated' and not updated:
                    updated = child.text or ''
            if title:
                entries.append({
                    'feed': feed_title or feed_url,
                    'title': title, 'link': link,
                    'desc': desc[:220],
                    'time': parse_date(updated),
                })

    entries.sort(key=lambda x: -x['time'])
    return entries[:PER_FEED]


def feeds_from_argv():
    return [a.strip() for a in sys.argv[1:] if a.strip().startswith('http')]


def feeds_from_file(path):
    feeds = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and line.startswith('http'):
                    feeds.append(line)
    except OSError:
        pass
    return feeds


def main():
    feeds = feeds_from_argv()
    if not feeds:
        env_file = os.environ.get('RSS_FEEDS_FILE', '')
        if env_file:
            feeds = feeds_from_file(env_file)
    if not feeds:
        legacy = os.path.expanduser(
            '~/.config/hypr/scripts/quickshell/ui/panels/rss-reader/feeds.txt')
        feeds = feeds_from_file(legacy)

    all_entries = []
    for url in feeds:
        all_entries.extend(fetch_feed(url))
        time.sleep(0.2)

    all_entries.sort(key=lambda x: -x['time'])
    print(json.dumps(all_entries[:TOTAL]))


if __name__ == '__main__':
    main()

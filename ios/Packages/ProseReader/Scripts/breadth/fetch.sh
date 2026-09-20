#!/bin/zsh
# Fetch each sourced pattern page as text into <work dir>/<id>/p01.txt, one request per page, two
# seconds apart (one request per site, as docs/research/corpus/sources.md asks). A 429 waits the
# Retry-After the server sent (at most two minutes) and tries once more. A page that fails leaves no
# file behind, and the script exits non-zero at the end after trying the rest.
# usage: Scripts/breadth/fetch.sh <work dir>
set -uo pipefail
W="$1"; here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../../../.." && pwd)"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
failed=0
fetch_page() {  # url html-file headers-file -> prints the HTTP status, 000 when curl itself failed
  local status
  if ! status=$(curl -sSL -m 60 -A "$UA" -D "$3" -o "$2" -w '%{http_code}' "$1" 2>/dev/null); then status=000; fi
  echo "$status"
}
word_count() { local n; if n=$(wc -w < "$1"); then echo "${n// /}"; else echo 0; fi; }
while IFS=$'\t' read -r id genre url; do
  [ -z "$id" ] && continue
  mkdir -p "$W/$id"
  [ -s "$W/$id/p01.txt" ] && { echo "have  $id"; continue; }
  html="$W/$id/page.html.part"; hdr="$W/$id/headers.part"; tmp="$W/$id/p01.txt.part"
  status=$(fetch_page "$url" "$html" "$hdr")
  if [ "$status" = "429" ]; then
    if ! wait=$(sed -n 's/^[Rr]etry-[Aa]fter: *\([0-9]\{1,3\}\).*/\1/p' "$hdr" | head -n 1); then wait=""; fi
    wait=${wait:-60}; [ "$wait" -gt 120 ] && wait=120; wait=$((wait + RANDOM % 10))  # a little spread
    echo "429   $id: waiting ${wait}s" >&2; sleep "$wait"
    status=$(fetch_page "$url" "$html" "$hdr")
  fi
  if [[ "$status" == 2?? ]] && uv run python "$root/docs/research/tools/html2txt.py" < "$html" > "$tmp" && [ "$(word_count "$tmp")" -ge 100 ]; then
    mv "$tmp" "$W/$id/p01.txt"; echo "ok    $id ($(word_count "$W/$id/p01.txt") words)"
  else
    echo "FAIL  $id HTTP $status $url" >&2; failed=1
  fi
  rm -f "$html" "$hdr" "$tmp"
  sleep 2
done < "$here/sources.tsv"
exit $failed

#!/usr/bin/env bash
# Yarnspirations product page -> Shopify CDN PDF -> text. Run from docs/research/corpus.
# Raw text is copyrighted and gitignored; only corpus.csv is committed.
set -u
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
DELAY="${DELAY:-8}"
mkdir -p raw pdf
while read -r slug technique; do
  [ -z "$slug" ] && continue
  case "$slug" in \#*) continue;; esac
  out="raw/ys-${slug}.txt"
  [ -s "$out" ] && { echo "have  $slug"; continue; }
  page="https://www.yarnspirations.com/products/${slug}"
  pdf=""
  for attempt in 1 2 3 4; do
    html=$(curl -sL -A "$UA" -w "\n__STATUS__%{http_code}" "$page")
    status=${html##*__STATUS__}
    if [ "$status" = "429" ]; then sleep $((DELAY * attempt * 3)); continue; fi
    pdf=$(printf '%s' "$html" | grep -oE 'https://cdn\.shopify\.com/[^"]+\.pdf' | sort -u | head -1)
    break
  done
  if [ -z "$pdf" ]; then echo "NOPDF $slug (status $status)"; sleep "$DELAY"; continue; fi
  curl -sL -A "$UA" -o "pdf/ys-${slug}.pdf" "$pdf" || { echo "DLFAIL $slug"; continue; }
  { echo "SOURCE: $page"; echo "PDF: $pdf"; echo "TECHNIQUE-HINT: $technique"; echo; pdftotext -layout "pdf/ys-${slug}.pdf" -; } > "$out" 2>/dev/null
  w=$(wc -w < "$out" | tr -d ' ')
  echo "ok    $slug ($w words)"
  sleep "$DELAY"
done <<'LIST'
# slug technique-hint
bernat-crochet-corner-to-corner-afghan c2c
caron-corner-to-corner-crochet-motifs-blanket c2c
bernat-corner-to-corner-crochet-cactus-blanket c2c
caron-corner-to-corner-crochet-blanket c2c
red-heart-corner-to-corner-crochet-throw c2c
bernat-corner-to-corner-crochet-school-bus-blanket c2c
caron-argyle-c2c-crochet-baby-blanket c2c
caron-corner-to-corner-popping-florals-crochet-graphghan c2c-graphghan
caron-corner-to-corner-pretty-florals-crochet-graphghan c2c-graphghan
gingerbread-house-blanket tapestry-graphghan
bernat-mosaic-crochet-blanket mosaic
caron-dotted-daze-mosaic-crochet-blanket-wrap mosaic
caron-frenetic-stripes-mosaic-crochet-blanket mosaic
bernat-mosaic-ombre-crochet-blanket mosaic
caron-mosaic-motifs-crochet-blanket mosaic
red-heart-evergreen-mosaic-crochet-blanket mosaic
caron-mosaic-diamonds-crochet-blanket mosaic
caron-woven-mosaic-crochet-blanket mosaic
bernat-prism-pathways-mosaic-crochet-blanket mosaic
red-heart-cottagecore-filet-crochet-throw filet
bernat-diamond-filet-crochet-blanket filet
bernat-velvety-filet-crochet-baby-blanket filet
bernat-lacy-squares-filet-crochet-baby-blanket filet
bernat-filet-crochet-dinosaur-baby-blanket filet
bernat-star-of-the-show-crochet-blanket filet
red-heart-timeless-tunisian-crochet-blanket tunisian
bernat-tunisian-honeycomb-crochet-blanket tunisian
caron-tunisian-crochet-woven-look-blanket tunisian
red-heart-tunisian-simple-stripes-crochet-blanket tunisian
caron-tunisian-full-stitch-crochet-blanket tunisian
red-heart-tunisian-entrelac-crochet-baby-blanket-50g tunisian
patons-fair-isle-border-knit-blanket-and-pillow knit-stranded
caron-fair-isle-knit-hat knit-stranded
patons-fair-isle-classic knit-stranded
caron-graphic-knit-fair-isle-hat knit-stranded
bernat-peachy-pillow-crochet-amigurumi spiral-rounds
red-heart-harper-hedgehog spiral-rounds
caron-spirals-throw rounds
peaches-creme-granny-square-crochet-dishcloth joined-rounds
lily-sugarn-cream-heart-dishcloth-crochet-blanket rounds
lily-sugarn-cream-scrubbing-in-the-round-crochet-dishcloth rounds
cotton-bloom-dishcloths rows
lily-sugarn-cream-basic-dishcloth rows
lily-crochet-right-stripe-dishcloth rows
bernat-crochet-dishcloth rows
bernat-dishcloth rows
red-heart-plaid-christmas-crochet-blanket rows
red-heart-beach-crochet-blanket rows
red-heart-hexagon-crochet-baby-blanket rounds
red-heart-personalized-crochet-baby-blanket graphghan
red-heart-aran-hearts-throw rows
red-heart-crochet-textured-throw rows
LIST
echo "---"; ls raw | wc -l

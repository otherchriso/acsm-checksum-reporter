#!/usr/bin/env bash
# test_notes_parsing.sh
# Temporary test to pipe production HTML notes through the parsing pipeline

# The notes parsing pipeline extracted from checker.sh
parse_notes() {
  local raw="${1}"
  local notes
  notes=$(echo "${raw}" \
    | tr '\r\n' ' ' \
    | sed 's|<a href="\([^"]*\)"[^>]*>\([^<]*\)</a>|__\2__ _(@LT@\1@GT@)_|g' \
    | sed "s|\"|'|g" \
    | sed 's|<br>|@NL@|g' \
    | sed 's|<p>|@NL@|g' \
    | sed 's|</p>|@NL@|g' \
    | sed 's|<ul>|@NL@|g' \
    | sed 's|<li>|• |g' \
    | sed 's|</li>|@NL@|g' \
    | sed 's|<[^>]*>||g' \
    | sed 's|&nbsp;| |g' \
    | sed 's|&gt;|>|g' \
    | sed 's|&lt;|<|g' \
    | sed "s|&quot;|\"|g" \
    | sed 's|&amp;|\&|g' \
    | sed 's|@LT@|<|g' \
    | sed 's|@GT@|>|g' )

  # De-duplicate self-referencing links: __URL__ _(<URL>)_ → <URL>
  notes=$(echo "${notes}" | sed -E 's|__([^_]+)__ _\(<\1>\)_|<\1>|g')

  # Convert @NL@ placeholders to real newlines, trim leading/trailing, compress runs
  notes=$(echo "${notes}" | sed 's|@NL@|\n|g' \
    | sed '/./,$!d' \
    | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' \
    | cat -s)

  # Strip notes that are effectively empty
  local notes_stripped=$(echo "${notes}" | xargs)
  [[ -z "${notes_stripped}" ]] && notes=""

  echo "${notes}"
}

echo "=== Test 1: Simple paragraph ==="
parse_notes '<p>This car requires the Assetto Corsa Dream Pack 1 DLC to be installed.</p>'
echo ""

echo "=== Test 2: Paragraph with <br> line break ==="
parse_notes '<p>This car has had at least two updates from RSS since it was released, despite remaining labelled as "Version 1". If you see checksum errors, find the email from when you purchased the car and download/reinstall a fresh copy.<br><br>The version installed at Occasional Racing was downloaded July 2, 2023.</p>'
echo ""

echo "=== Test 3: Multiple paragraphs ==="
parse_notes '<p>Version 1.3</p><p><span style="background-color: unset; font-size: 1rem;">For any issues with crashes at track loading, try renaming or removing crew_anim.ksanim in the extension folder.</span><br></p>'
echo ""

echo "=== Test 4: Hyperlink (named) ==="
parse_notes '<p>More info on this car as part of the <a href="https://www.patreon.com/posts/gt4-1-0-release-114723997" target="_blank">Guerilla Mods GT4 pack v1.0 release </a> is freely available via their Patreon.</p>'
echo ""

echo "=== Test 5: Hyperlink (self-referencing URL as link text) ==="
parse_notes '<p>Replacement badges and names for the real world cars can be found at <a href="https://www.racedepartment.com/downloads/rss-gt-pack-real-in-game-names.22659/" target="_blank">https://www.racedepartment.com/downloads/rss-gt-pack-real-in-game-names.22659/</a></p>'
echo ""

echo "=== Test 6: Bare URL in text (no anchor tag) ==="
parse_notes '<p>CSP v0.2.8 or newer required. The car version installed here is currently v1.3.3 per&nbsp;https://www.overtake.gg/downloads/porsche-911-singer.29318/history</p>'
echo ""

echo "=== Test 7: Multiple hyperlinks with surrounding text ==="
parse_notes '<p>From&nbsp;<a href="http://www.mediafire.com/file/rnlbryt2vdbxr5y/AVRP_Update_1_2_by_Uncle_M.rar/file" target="_blank">mediafire.com</a><span style="font-family: stuff; font-size: 1rem;">&nbsp;via&nbsp;</span><a href="https://acmods.net/cars/australian-vintage-race-pack/" style="font-family: stuff;">https://acmods.net/cars/australian-vintage-race-pack/</a></p><p><br></p>'
echo ""

echo "=== Test 8: Bullet list (<ul>/<li>) ==="
parse_notes '<p>This download contains the following things, pre-merged and ready to race:</p><ul><li><span style="background-color: unset; font-size: 1rem;">Original track download from <a href="https://www.racedepartment.com/downloads/parco-roccio.48542/" target="_blank">https://www.racedepartment.com/downloads/parco-roccio.48542/</a></span></li><li><span style="background-color: unset; font-size: 1rem;">CSP updates and fixes from <a href="https://www.racedepartment.com/downloads/parco-roccio-csp-update-fixes-by-crist86.50843/" target="_blank">https://www.racedepartment.com/downloads/parco-roccio-csp-update-fixes-by-crist86.50843/</a></span></li></ul>'
echo ""

echo "=== Test 9: Real \\r\\n in input (multi-paragraph DLC note) ==="
printf '<p>Please note: this mod requires <a href="https://store.steampowered.com/app/423630/Assetto_Corsa__Dream_Pack_3/" target="_blank">Dream Pack 3 DLC</a>.</p>\r\n\r\n<p>The single download link provided here includes the 2019-08-13 dated version of the mod pack.</p>\r\n\r\n<p>\r\n<a href="http://www.mediafire.com/file/pgl321oqb2jq225/GPL1500.7z/file" target="_blank">original mod download</a></p>' | while IFS= read -r line; do echo "$line"; done | {
  input=$(cat)
  parse_notes "${input}"
}
echo ""

echo "=== Test 10: nbsp-heavy content ==="
parse_notes '<p><span style="background-color: rgba(20, 20, 20, 0.5);">Version 1.2.2 installed here, updated January 18, 2026. Find out about the car, including how to switch on the ignition, at&nbsp;</span><a href="https://www.patreon.com/posts/alfa-romeo-tz2-1-95168367" style="background-color: rgba(20, 20, 20, 0.5);">https://www.patreon.com/posts/alfa-romeo-tz2-1-95168367</a><span style="background-color: rgba(20, 20, 20, 0.5);">&nbsp;(no sign up or payment required to view this post)</span></p>'
echo ""

echo "=== Test 11: Empty paragraph (should be empty) ==="
result=$(parse_notes '<p><br></p>')
if [[ -z "${result}" ]]; then
  echo "(correctly empty)"
else
  echo "BUG: got '${result}'"
fi
echo ""

echo "=== Test 12: Mock 'full' scenario notes (literal \\n in bash string) ==="
notes="Updated physics for competitive racing.\nVersion must match server exactly."
echo "Raw value: ${notes}"
echo "This is what the mock passes to render_template - the \\n is a literal backslash-n"
echo ""

echo "=== Test 13: HTML entities (&gt; &lt; &amp; &quot;) ==="
parse_notes '<p>Navigate to Content&gt;Cars menu. Use &lt;brackets&gt; and &amp; symbols. He said &quot;hello&quot;.</p>'
echo ""

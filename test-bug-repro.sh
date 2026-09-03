#!/bin/bash
# Test file for BUG reproduction

cat <<'EOF' > /tmp/example.txt
	indented with a real TAB character above
    indented with 4 spaces here
line with trailing spaces here   
EOF

# Regex/backslash sanity checks
echo "s/foo\(.*\)bar/\1/" 
grep -P '\bword\b'
grep -P '\d+\.\d+'
printf "literal backslash-n: \\n literal backslash-t: \\t\n"

if [[ "$1" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
  echo "major=\1 minor=\2"
fi

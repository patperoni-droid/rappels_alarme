#!/usr/bin/env bash
set -e
BR="chat/review"
FILE="$1"
[ -z "$FILE" ] && echo "Usage: ./share.sh chemin/fichier" && exit 1
git checkout -B "$BR"
git add "$FILE"
git commit -m "Review: $FILE"
git push -u origin "$BR"
echo "OK. Dis à Roxane: fichier $FILE est sur branche $BR."
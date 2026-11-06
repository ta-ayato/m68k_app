#!/bin/sh
# .include "xxx.s" を展開して 1 ファイルにまとめる（提出用: テキスト付録 A.6.3.2）。
# 展開は 1 段だけ（os_*.s の中で .include は使わないこと）。
# リポジトリの直下で実行する。出力もリポジトリの直下にできる。
#   使い方: sh tools/bundle.sh main_echo.s simple_os.s   → simple_os.s ができる
#   確認:   m68k-as -t 400 simple_os.s で元と同じようにアセンブルできること
set -e

if [ $# -ne 2 ]; then
    echo "usage: sh tools/bundle.sh <entry.s> <output.s>" >&2
    exit 1
fi

out="$2"
# 元のファイルを上書きしないようにする
case "$out" in
    "$1"|os_*.s|user_*.s|main_*.s|*/*)
        echo "bundle.sh: 出力名 $out は使えない（元のファイルと重なるか，パスを含んでいる）" >&2
        exit 1 ;;
esac

awk '
/^[ \t]*\.include[ \t]+"/ {
    match($0, /"[^"]+"/)
    f = substr($0, RSTART + 1, RLENGTH - 2)
    print "| ======== begin " f " ========"
    while ((getline line < f) > 0) print line
    close(f)
    print "| ======== end " f " ========"
    next
}
{ print }
' "$1" > "$out"
echo "wrote $out" >&2

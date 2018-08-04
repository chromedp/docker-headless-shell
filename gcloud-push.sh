#!/bin/bash

set -e

SRC=$(realpath $(cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))

pushd $SRC/out &> /dev/null

rm -f available.txt latest.txt
for i in *.bz2; do
  echo $i >> available.txt
done

ls *.bz2|sort -r -V|head -1 > latest.txt

popd &> /dev/null

set -v

gsutil -m rsync -r -d -x .gitignore $SRC/out/ gs://docker-headless-shell/
gsutil -m acl -r set public-read gs://docker-headless-shell/

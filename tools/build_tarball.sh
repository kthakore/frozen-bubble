#!/bin/sh

version=`cat VERSION`
file="/tmp/frozen-bubble-$version.tar.bz2"
tar --transform="s||frozen-bubble-$version/|" -jcvf $file *
echo
echo "Built $file"

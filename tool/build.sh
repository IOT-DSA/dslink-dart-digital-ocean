#!/usr/bin/env bash
if [ -d build ]
then
  rm -rf build
fi

mkdir build

pub get
cp -R -L packages/ build/
cp -R bin lib build/
dart tool/package_map.dart
cd build
zip -r ../../../files/digital_ocean.zip .

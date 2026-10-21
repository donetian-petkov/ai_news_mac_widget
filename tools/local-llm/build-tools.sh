#!/bin/bash
# Builds the two small read-only helpers the guard and the run use: macOS's heat level and the fan speeds.
set -e
cd "$(dirname "$0")"; mkdir -p bin
swiftc -O -o bin/thermal src/thermal.swift
clang -O2 -o bin/fans src/fans.c -framework IOKit
echo "built bin/thermal bin/fans"

#!/bin/bash
cd ~/Games/GC/ModernGekko-Template
exec ./lib/ModernGekko/build/moderngekko-run \
  --game extracted/rebel-strike \
  --allow-interpreter "$@"

#!/usr/bin/env python3
"""Emit deterministic qualification outcomes without requiring an EDA tool."""

from __future__ import annotations

import argparse
import sys


parser = argparse.ArgumentParser()
parser.add_argument("--diagnostic", required=True)
parser.add_argument("--exit-code", required=True, type=int)
arguments = parser.parse_args()

print(arguments.diagnostic)
sys.exit(arguments.exit_code)

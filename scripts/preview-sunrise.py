#!/usr/bin/env python3
"""Compatibility entry point for the Sunrise cloud QA preview."""
import argparse
import importlib.util
from pathlib import Path
path=Path(__file__).with_name('preview-artworks.py')
spec=importlib.util.spec_from_file_location('artwork_preview',path)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=module.ROOT/'dist/sunrise-preview')
    module.generate(parser.parse_args().output,'impression-sunrise')

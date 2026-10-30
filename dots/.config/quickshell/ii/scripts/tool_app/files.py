"""Local file URLs, atomic JSON writes and no-overwrite Linux renames."""
import ctypes
import json
import os
from pathlib import Path
import tempfile
from urllib.parse import unquote, urlparse


def local_path(value):
    value = os.fspath(value)
    return Path(unquote(urlparse(value).path) if value.startswith('file:') else value).expanduser().resolve()


def atomic_json(target, value):
    target = local_path(target)
    fd, name = tempfile.mkstemp(dir=target.parent, prefix='.'+target.name)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, indent=2, allow_nan=False)
            f.write('\n')
        os.replace(name, target)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def rename_no_replace(source, target):
    """Atomic Linux rename that cannot overwrite an existing sibling."""
    libc=ctypes.CDLL(None,use_errno=True)
    rename=libc.renameat2
    rename.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]
    rename.restype=ctypes.c_int
    if rename(-100,os.fsencode(source),-100,os.fsencode(target),1)!=0:
        number=ctypes.get_errno()
        raise OSError(number,os.strerror(number),str(target))

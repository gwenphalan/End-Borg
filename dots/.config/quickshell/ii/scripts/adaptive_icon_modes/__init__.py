"""Image-only approved V3 adaptive artwork and container finishing.

Compose the returned variant with the selected family backplate, call
resolve_container(variant, composed, mode), then compose the result again.
A None backplate keeps the selected family color. The fit presentation
must not be pre-fitted: compose_icon performs its one optical placement.
"""
from .candidate import render_variant, resolve_container

__all__ = ["render_variant", "resolve_container"]

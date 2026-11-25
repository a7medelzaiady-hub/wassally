#!/usr/bin/env python3
"""Split the approved landing artwork into reusable, independently sized JPEGs.

Run once when updating assets/images/customer_entry_reference.jpg.
Requires Pillow: python -m pip install Pillow
"""
from pathlib import Path
from PIL import Image

source = Path("assets/images/customer_entry_reference.jpg")
output = source.parent / "entry"
output.mkdir(parents=True, exist_ok=True)
regions = {
    "wasally_logo.jpg": (247, 156, 221, 173),
    "hero_food.jpg": (12, 311, 310, 207),
    "quick_delivery.jpg": (20, 541, 303, 195),
    "offers.jpg": (22, 796, 295, 173),
    "stores.jpg": (22, 1026, 305, 174),
}
with Image.open(source) as image:
    image = image.convert("RGB")
    for filename, (x, y, width, height) in regions.items():
        image.crop((x, y, x + width, y + height)).save(
            output / filename, format="JPEG", quality=88, optimize=True
        )
        print(output / filename)

"""Regenerate KORA brand assets from the logo mark.

K mark = three overlapping rounded capsules (translucent violet layers):
  - vertical stem          lightest lilac
  - lower-right diagonal   medium violet
  - upper-right diagonal   deep violet (drawn last, on top)
Overlaps darken naturally via alpha compositing, matching the logo.
Outputs:
  assets/brand/kora_logo_k.png    transparent 1024 mark (in-app splash)
  assets/brand/kora_logo_fg.png   transparent adaptive-icon foreground
  assets/brand/kora_logo.png      1024 icon on white rounded square
  assets/brand/kora_logo_full.png 2048x640 lockup: mark + KORA wordmark
"""
from PIL import Image, ImageDraw, ImageFont
import os

OUT = os.path.join(os.path.dirname(__file__), '..', 'app', 'assets', 'brand')

STEM = (216, 204, 255, 255)    # light lilac
LOWER = (167, 139, 250, 255)   # medium violet
UPPER = (139, 92, 246, 255)    # KORA primary violet
NAVY = (30, 27, 50, 255)       # wordmark navy
WHITE = (251, 250, 255, 255)


def capsule(draw, box, radius, color):
    draw.rounded_rectangle(box, radius=radius, fill=color)


def rotated_capsule(size, length, thick, angle_deg, color):
    """Capsule drawn on its own layer then rotated."""
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = size[0] / 2, size[1] / 2
    # capsule horizontal along x, centered at origin point (0,0 of layer center)
    x0 = cx - length / 2
    y0 = cy - thick / 2
    capsule(d, (x0, y0, x0 + length, y0 + thick), thick / 2, color)
    return layer.rotate(angle_deg, resample=Image.BICUBIC,
                        center=(cx, cy))


def draw_mark(size=1024, mark_scale=0.62, center=(0.5, 0.5)):
    """Return RGBA image with the K mark centered."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    S = size * mark_scale          # mark bounding height
    thick = S * 0.16               # capsule thickness
    stem_h = S * 0.86
    arm_len = S * 0.78
    cx, cy = size * center[0], size * center[1]

    # Stem
    stem = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(stem)
    sx = cx - arm_len * 0.24       # stem x offset (left of center)
    capsule(d, (sx - thick / 2, cy - stem_h / 2,
                sx + thick / 2, cy + stem_h / 2), thick / 2, STEM)
    img.alpha_composite(stem)

    # Lower arm: from joint up-right? K lower arm goes down-right.
    # Joint is at stem middle.
    joint = (sx + thick * 0.55, cy)
    for angle, col in ((40, LOWER), (-42, UPPER)):
        arm = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(arm)
        # capsule anchored at joint, pointing right
        x0 = joint[0] - arm_len * 0.08
        capsule(d, (x0, joint[1] - thick / 2,
                    x0 + arm_len, joint[1] + thick / 2), thick / 2, col)
        arm = arm.rotate(angle, resample=Image.BICUBIC,
                         center=joint)
        img.alpha_composite(arm)
    return img


def rounded_square(size, radius_ratio=0.235):
    """iOS-style squircle-ish rounded rect mask."""
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=int(size * radius_ratio), fill=255)
    return mask


def main():
    os.makedirs(OUT, exist_ok=True)

    # 1) transparent mark for in-app use
    mark = draw_mark(1024, mark_scale=0.60, center=(0.5, 0.5))
    mark.save(os.path.join(OUT, 'kora_logo_k.png'))

    # 2) adaptive foreground — mark inside ~66% safe zone
    fg = draw_mark(1024, mark_scale=0.42, center=(0.5, 0.5))
    fg.save(os.path.join(OUT, 'kora_logo_fg.png'))

    # 3) launcher icon — white rounded square + mark
    icon = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    bg = Image.new('RGBA', (1024, 1024), WHITE)
    icon.paste(bg, (0, 0), rounded_square(1024))
    inner = draw_mark(1024, mark_scale=0.56)
    icon.alpha_composite(inner)
    icon.save(os.path.join(OUT, 'kora_logo.png'))

    # 4) full lockup for store listing / share cards
    W, H = 2048, 640
    lock = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    m = draw_mark(640, mark_scale=0.78)
    lock.alpha_composite(m, (40, 0))
    font = None
    for cand in ('c:/Windows/Fonts/segoeuib.ttf',
                 'c:/Windows/Fonts/arialbd.ttf',
                 'c:/Windows/Fonts/calibrib.ttf'):
        if os.path.exists(cand):
            font = ImageFont.truetype(cand, 300)
            break
    d = ImageDraw.Draw(lock)
    d.text((760, 155), 'KORA', font=font, fill=NAVY)
    lock.save(os.path.join(OUT, 'kora_logo_full.png'))

    print('wrote:', os.listdir(OUT))


if __name__ == '__main__':
    main()

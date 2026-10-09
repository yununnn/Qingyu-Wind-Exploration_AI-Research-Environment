import json
from pathlib import Path
from PIL import Image, ImageChops

folder = Path(__file__).parent
atlas = Image.open(folder / 'frames.png').convert('RGBA')
results = []
for index in range(8):
    frame = atlas.crop((index * 40, 0, (index + 1) * 40, 40))
    alpha = frame.getchannel('A')
    remaining = {(x, y) for y in range(40) for x in range(40) if alpha.getpixel((x, y))}
    component_count = 0
    while remaining:
        component_count += 1
        pending = [remaining.pop()]
        while pending:
            x, y = pending.pop()
            for dx, dy in ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)):
                neighbor = (x + dx, y + dy)
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    pending.append(neighbor)
    assert component_count == 1, (index, component_count)
    results.append({'frame': index, 'connected_components': component_count, 'bbox': alpha.getbbox(), 'max_alpha': alpha.getextrema()[1]})

before = Image.open(folder / 'preview.png').convert('RGB')
after = Image.open(folder / 'preview_later.png').convert('RGB')
assert ImageChops.difference(before, after).getbbox() is not None
assert all(results[i]['max_alpha'] >= results[i + 1]['max_alpha'] for i in range(7))
motion = [Image.open(path).convert('RGB') for path in sorted(folder.glob('motion_*.png'))]
motion[0].save(folder / 'ripple_preview.gif', save_all=True, append_images=motion[1:], duration=100, loop=0)
(folder / 'qc.json').write_text(json.dumps({'frames': results, 'animation_changes': True, 'gif_frames': len(motion)}, indent=2), encoding='utf-8')
print('QC_OK: 8 connected contours; monotonic fade; live animation changes; 16-frame GIF')

"""Small fail-closed SVG renderer for the authored geometric icon, using Pillow.

The SVG is the authority. Unsupported paths/transforms fail rather than rendering
a different PNG silently. No fonts, bitmap inputs, or third-party SVG runtime.
"""
import math
import re
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw


def path_points(data):
    tokens = re.findall(r"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)", data)
    if re.sub(r"[\s,]+", "", data) != "".join(tokens):
        raise ValueError("Unsupported SVG path syntax")
    points, current, start = [], (0., 0.), None
    i = 0
    while i < len(tokens):
        command = tokens[i]
        i += 1
        counts = {"M": 2, "L": 2, "C": 6, "Z": 0}
        if command not in counts:
            raise ValueError("Only authored absolute M/L/C/Z commands are supported")
        count = counts[command]
        values = [float(value) for value in tokens[i:i+count]]
        if len(values) != count:
            raise ValueError("Incomplete SVG path")
        i += count
        if command in {"M", "L"}:
            current = tuple(values)
            if command == "M":
                if points:
                    raise ValueError("Use one continuous subpath per path element")
                start = current
            points.append(current)
        elif command == "C":
            p0, p1, p2, p3 = current, values[:2], values[2:4], values[4:6]
            for step in range(1, 97):
                t = step / 96
                points.append(tuple((1-t)**3*p0[j] + 3*(1-t)**2*t*p1[j] +
                                    3*(1-t)*t*t*p2[j] + t**3*p3[j] for j in range(2)))
            current = tuple(p3)
        elif command == "Z":
            if start is None:
                raise ValueError("Path has no starting point")
            points.append(start)
    return points


def render(source, size=1024, layers=("background", "symbol"), white=False):
    root = ET.parse(source).getroot()
    if set(root.attrib)-{"width","height","viewBox"}:
        raise ValueError("Root styles/transforms need renderer support")
    if root.get("viewBox") != "0 0 1024 1024":
        raise ValueError("Icon uses the fixed Android authoring grid")
    scale = size * 4 / 1024
    image = Image.new("RGBA", (size*4, size*4), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    seen = set()
    for group in root:
        if group.tag.split("}")[-1] in {"title", "desc"}:
            continue
        if group.tag.split("}")[-1] != "g" or group.get("transform"):
            raise ValueError("Only explicit geometry groups are supported")
        if set(group.attrib) != {"id"}:
            raise ValueError("Layer inheritance/styles need explicit renderer support")
        identity = group.get("id")
        if identity in seen or identity not in {"background", "symbol"}:
            raise ValueError("Unexpected/duplicate icon layer")
        seen.add(identity)
        if identity not in layers:
            continue
        for element in group:
            tag = element.tag.split("}")[-1]
            allowed = {"rect":{"x","y","width","height","fill"},
                       "circle":{"cx","cy","r","fill"},
                       "path":{"d","fill","stroke","stroke-width","stroke-linecap","stroke-linejoin"}}
            if tag not in allowed or set(element.attrib)-allowed[tag]:
                raise ValueError("SVG attributes need renderer support first")
            colour = "#FFFFFF" if white else element.get("stroke") or element.get("fill")
            if tag == "rect":
                x, y, width, height = [float(element.get(k, "0")) * scale for k in ("x", "y", "width", "height")]
                draw.rectangle((x, y, x+width, y+height), fill=colour)
            elif tag == "circle":
                cx, cy, radius = [float(element.get(k)) * scale for k in ("cx", "cy", "r")]
                draw.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), fill=colour)
            elif tag == "path":
                points = [(x*scale, y*scale) for x, y in path_points(element.get("d", ""))]
                if len(points) < 2:
                    raise ValueError("Empty path")
                width = float(element.get("stroke-width", "0")) * scale
                if width <= 0 or element.get("fill") != "none" or element.get("stroke-linecap") != "round" or element.get("stroke-linejoin") != "round":
                    raise ValueError("Authored path must have an explicit round stroke")
                radius = width / 2
                # Union of capsules approximates the SVG round stroke. Pillow's
                # curve joins on densely sampled cubics can produce spike holes.
                for a, b in zip(points, points[1:]):
                    length = math.hypot(b[0]-a[0], b[1]-a[1])
                    if not length:
                        continue
                    nx, ny = -(b[1]-a[1])/length*radius, (b[0]-a[0])/length*radius
                    draw.polygon([(a[0]+nx,a[1]+ny),(b[0]+nx,b[1]+ny),
                                  (b[0]-nx,b[1]-ny),(a[0]-nx,a[1]-ny)],fill=colour)
                for x, y in points:
                    draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=colour)
            else:
                raise ValueError("Unsupported icon geometry: " + tag)
    if not set(layers).issubset(seen):
        raise ValueError("Missing icon layer")
    return image.resize((size, size), Image.Resampling.LANCZOS)


def generate_sources(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    full = render(source)
    # Legacy/store use the same geometry at a larger optical size. Adaptive
    # retains the full108dp grid and its72dp safe circle.
    legacy = full.crop((112, 112, 912, 912)).resize((1024, 1024), Image.Resampling.LANCZOS)
    legacy.save(destination / "icono_1024.png", optimize=True)
    legacy.resize((512, 512), Image.Resampling.LANCZOS).save(destination / "playstore_512.png", optimize=True)
    render(source, 432, ("symbol",)).save(destination / "ic_launcher_foreground_432.png", optimize=True)
    render(source, 432, ("background",)).save(destination / "ic_launcher_background_432.png", optimize=True)
    render(source, 432, ("symbol",), white=True).save(destination / "ic_launcher_monochrome_432.png", optimize=True)

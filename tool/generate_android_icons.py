#!/usr/bin/python3
"""Genera recursos Android desde el SVG original; requiere las bibliotecas del sistema librsvg y Cairo.
Ejecutar: /usr/bin/python3 tool/generate_android_icons.py
Sin descargas ni dependencias Flutter adicionales.
"""
from pathlib import Path
import xml.etree.ElementTree as ET
import ctypes as C
from ctypes.util import find_library

def api(lib, name, result, *arguments):
    f = getattr(lib, name)
    f.restype = result
    f.argtypes = arguments
    return f

rsvg = C.CDLL(find_library('rsvg-2'))
cairo = C.CDLL(find_library('cairo'))
gobject = C.CDLL(find_library('gobject-2.0'))
load = api(rsvg, 'rsvg_handle_new_from_file', C.c_void_p, C.c_char_p, C.c_void_p)
render_cairo = api(rsvg, 'rsvg_handle_render_cairo', C.c_int, C.c_void_p, C.c_void_p)
create_surface = api(cairo, 'cairo_image_surface_create', C.c_void_p, C.c_int, C.c_int, C.c_int)
create_context = api(cairo, 'cairo_create', C.c_void_p, C.c_void_p)
scale = api(cairo, 'cairo_scale', None, C.c_void_p, C.c_double, C.c_double)
write_png = api(cairo, 'cairo_surface_write_to_png', C.c_int, C.c_void_p, C.c_char_p)
free_context = api(cairo, 'cairo_destroy', None, C.c_void_p)
free_surface = api(cairo, 'cairo_surface_destroy', None, C.c_void_p)
unref = api(gobject, 'g_object_unref', None, C.c_void_p)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/icon/openbkool.svg'
RES = ROOT / 'android/app/src/main/res'
NS = '{http://www.w3.org/2000/svg}'
svg = ET.parse(SOURCE).getroot()
background = svg.find(NS + 'rect').attrib['fill']
group = svg.find(NS + 'g')
paths = [p.attrib['d'] for p in group.findall(NS + 'path')]

def render(size, target):
    surface = create_surface(0, size, size)  # CAIRO_FORMAT_ARGB32
    context = create_context(surface)
    handle = load(str(SOURCE).encode(), None)
    if not handle:
        raise RuntimeError('No se puede leer el SVG')
    try:
        scale(context, size / 512, size / 512)
        if not render_cairo(handle, context):
            raise RuntimeError('No se puede renderizar el SVG')
        target.parent.mkdir(parents=True, exist_ok=True)
        if write_png(surface, str(target).encode()) != 0:
            raise RuntimeError(f'No se puede escribir {target}')
    finally:
        unref(handle)
        free_context(context)
        free_surface(surface)

for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    render(size, RES / f'mipmap-{density}/ic_launcher.png')
render(512, SOURCE.with_suffix('.png'))

vector = ['<?xml version="1.0" encoding="utf-8"?>',
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">']
for path in paths:
    vector.append(f'    <path android:pathData="{path}" android:fillColor="@android:color/transparent" android:strokeColor="{group.attrib["stroke"]}" android:strokeWidth="{group.attrib["stroke-width"]}" android:strokeLineCap="round" android:strokeLineJoin="round"/>')
vector.append('</vector>')
(RES / 'drawable/ic_launcher_foreground.xml').write_text('\n'.join(vector) + '\n')
(RES / 'values/icon_colors.xml').write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{background}</color>
</resources>
''')
(RES / 'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
''')
# Android 13+: el lanzador decide el color si el usuario activa iconos temáticos.
target = RES / 'mipmap-anydpi-v33/ic_launcher.xml'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
''')
print('SVG → PNG 48/72/96/144/192/512 y recursos adaptativos Android 26+/33+')

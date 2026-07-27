"""Genera assets/AndroidTV.ico: un televisor retro con pantalla verde Android.

Se dibuja a 2048 px y se reduce con LANCZOS, que es lo que da los bordes
suaves. El .ico se guarda DESDE LA IMAGEN GRANDE pasando sizes=[...]: si se
usa append_images, Pillow guarda un solo tamano y el icono sale borroso en
la barra de tareas.

    python hacer_icono.py
"""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path

S = 2048                      # lienzo de trabajo
VERDE = (61, 220, 132)        # #3DDC84, el verde de Android
TEAL = (0, 172, 193)
CARCASA = (38, 44, 52)
CARCASA_LUZ = (58, 66, 77)
BORDE = (24, 28, 34)


def gradiente(size, arriba, abajo):
    """Degradado vertical."""
    w, h = size
    g = Image.new("RGB", (1, h))
    px = g.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(int(arriba[i] + (abajo[i] - arriba[i]) * t) for i in range(3))
    return g.resize((w, h), Image.BICUBIC)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # --- Antenas -----------------------------------------------------------
    cx = S // 2
    base_y = int(S * 0.315)
    for dx, tip in ((-1, (int(S * 0.235), int(S * 0.085))),
                    (+1, (int(S * 0.765), int(S * 0.085)))):
        d.line([(cx + dx * 20, base_y), tip], fill=CARCASA_LUZ, width=34)
        d.ellipse([tip[0] - 46, tip[1] - 46, tip[0] + 46, tip[1] + 46],
                  fill=VERDE)

    # --- Patas -------------------------------------------------------------
    for x in (int(S * 0.235), int(S * 0.685)):
        d.rounded_rectangle([x, int(S * 0.815), x + int(S * 0.08), int(S * 0.885)],
                            radius=26, fill=BORDE)

    # --- Carcasa -----------------------------------------------------------
    caja = [int(S * 0.085), int(S * 0.30), int(S * 0.915), int(S * 0.83)]
    d.rounded_rectangle(caja, radius=118, fill=CARCASA, outline=BORDE, width=14)

    # --- Pantalla ------------------------------------------------------------
    # Se compone ENTERA (degradado + brillo + play) y se pega UNA sola vez.
    # Pegarla por capas con la misma mascara opaca borra lo anterior: la mascara
    # vale 255 dentro del rectangulo, asi que el paste reemplaza en vez de sumar.
    pant = [int(S * 0.135), int(S * 0.35), int(S * 0.865), int(S * 0.755)]
    pw, ph = pant[2] - pant[0], pant[3] - pant[1]

    pantalla = gradiente((pw, ph), VERDE, TEAL).convert("RGBA")

    # Triangulo de play, centrado en la pantalla
    r = int(S * 0.10)
    ccx, ccy = pw // 2, ph // 2
    capa = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    ImageDraw.Draw(capa).polygon(
        [(ccx - r * 0.55, ccy - r), (ccx - r * 0.55, ccy + r), (ccx + r * 0.95, ccy)],
        fill=(255, 255, 255, 240))
    pantalla = Image.alpha_composite(pantalla, capa)

    # Brillo diagonal por encima de todo
    gloss = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).polygon(
        [(0, 0), (int(pw * 0.62), 0), (int(pw * 0.20), ph), (0, ph)],
        fill=(255, 255, 255, 30))
    pantalla = Image.alpha_composite(pantalla, gloss)

    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=74, fill=255)
    img.paste(pantalla, (pant[0], pant[1]), mask)

    # --- Piloto de encendido ------------------------------------------------
    d = ImageDraw.Draw(img)
    ly = int(S * 0.792)
    d.ellipse([cx - 20, ly - 20, cx + 20, ly + 20], fill=VERDE)

    # --- Resplandor suave por detras ---------------------------------------
    glow = img.filter(ImageFilter.GaussianBlur(26))
    img = Image.alpha_composite(Image.blend(glow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), 0.55), img)

    # --- Guardar ------------------------------------------------------------
    out = Path(__file__).parent / "assets"
    out.mkdir(exist_ok=True)
    grande = img.resize((512, 512), Image.LANCZOS)
    grande.save(out / "AndroidTV.png")
    # sizes=[...] es lo que hace que el .ico lleve TODOS los tamanos nitidos
    grande.save(out / "AndroidTV.ico",
                sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                       (64, 64), (128, 128), (256, 256)])
    print(f"Generado: {out / 'AndroidTV.ico'}")
    print(f"Generado: {out / 'AndroidTV.png'}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""从设计稿裁出菜单栏火箭图标的各帧。

设计稿 `tray-source.png` 上排是静态态与运行态两张大图，下排是五帧动画。
这里取静态态与五帧，输出等高的 PNG。

两处关键处理：

1. 尺度与位置都按「机身像素」归一，机身指排除橙黄尾焰后的部分。
   尾焰长度逐帧变化，按整图外框对齐会让机身随尾焰前后漂移。
   原稿五帧之间本身还有约 4% 的尺寸差，因此先按机身面积的平方根折算到同一尺度，
   再按机身质心做亚像素平移对齐。

2. 内容裁到贴边，不留透明边距。tray-icon 把图标按 18 点高渲染（见其
   `platform_impl/macos/mod.rs`），整张图的高度都算进这 18 点，
   留白等于白白缩小可见面积。六帧统一裁到对齐后的并集外框，既贴边又不跳动。
"""
from PIL import Image

SRC = "src-tauri/icons/tray-source.png"
OUT = "src-tauri/icons/"
OUT_H = 36  # 18 点 @2x
ALPHA_TH = 24
PAD = 200  # 对齐用的工作画布余量

STATIC_BOX = (338, 167, 583, 424)
FRAME_BOXES = [
    (135, 682, 288, 840),
    (424, 683, 577, 842),
    (704, 680, 858, 841),
    (990, 681, 1147, 848),
    (1274, 680, 1426, 838),
]
NAMES = ["tray-idle"] + [f"tray-run-{i}" for i in range(1, 6)]


def body_stats(im):
    """机身（排除尾焰）的像素数与质心。

    面积与质心取的是整片区域，样本大，不像外框或舷窗那样容易被边缘抗锯齿带偏。
    尾焰是橙黄色，按颜色排除。
    """
    p = im.load()
    xs = ys = n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = p[x, y]
            if a < 128:
                continue
            if r > 190 and g > 110 and b < 150:  # 尾焰
                continue
            xs += x; ys += y; n += 1
    if not n:
        raise SystemExit("未找到机身，检查取材位置或颜色阈值")
    return n, xs / n, ys / n


def content_box(im):
    p = im.load()
    x1, y1, x2, y2 = im.width, im.height, -1, -1
    for y in range(im.height):
        for x in range(im.width):
            if p[x, y][3] >= ALPHA_TH:
                x1 = min(x1, x); y1 = min(y1, y)
                x2 = max(x2, x); y2 = max(y2, y)
    return x1, y1, x2, y2


def main():
    src = Image.open(SRC).convert("RGBA")
    sprites = [src.crop(STATIC_BOX)] + [src.crop(b) for b in FRAME_BOXES]

    # 静态态那张画得比动画帧大，五帧之间也有约 4% 的尺寸差。
    # 按机身面积的平方根折算到同一尺度：面积正比于线度的平方。
    ref = body_stats(sprites[1])[0] ** 0.5
    scaled = []
    for sp in sprites:
        k = ref / body_stats(sp)[0] ** 0.5
        scaled.append(
            sp if abs(k - 1) < 0.005
            else sp.resize((round(sp.width * k), round(sp.height * k)), Image.LANCZOS)
        )

    # 舷窗质心对齐到同一张工作画布。用仿射变换做亚像素平移——
    # 整像素取整会留下不到一格的残差，降采样后仍表现为机身轻微抖动
    big = max(max(s.size) for s in scaled) + PAD * 2
    placed = []
    for sp in scaled:
        _, cx, cy = body_stats(sp)
        canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        canvas.alpha_composite(sp, (PAD, PAD))
        dx = big / 2 - (PAD + cx)
        dy = big / 2 - (PAD + cy)
        placed.append(
            canvas.transform(
                (big, big), Image.AFFINE, (1, 0, -dx, 0, 1, -dy), Image.BICUBIC
            )
        )

    # 并集外框，六帧统一裁这一块
    us = [content_box(c) for c in placed]
    ux1 = min(b[0] for b in us); uy1 = min(b[1] for b in us)
    ux2 = max(b[2] for b in us); uy2 = max(b[3] for b in us)
    uw, uh = ux2 - ux1 + 1, uy2 - uy1 + 1
    out_w = max(1, round(uw * OUT_H / uh))

    for name, c in zip(NAMES, placed):
        c.crop((ux1, uy1, ux2 + 1, uy2 + 1)) \
         .resize((out_w, OUT_H), Image.LANCZOS) \
         .save(f"{OUT}{name}.png")
    print(f"并集外框 {uw}×{uh}，输出 {out_w}×{OUT_H}")


if __name__ == "__main__":
    main()

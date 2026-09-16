#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scr_capture.py — 接收 Zephyr+LVGL 截屏帧并转 PNG
帧格式:  "SCRSHOT <w> <h> <stride> <cf>\r\n" + raw(stride*h) + "SCRSHOT_END\r\n"
cf: 8 = L8 灰阶
用法:   python scr_capture.py -p COM5 -o ui.png
 依赖:   pyserial + Pillow (pip install pyserial pillow)
"""
import argparse
import sys


def find_framebuf(buf):
    """在缓冲里找帧头/帧尾边界，返回 (head_index, raw_start, raw_len, meta) 或不完整时的 None"""
    head = buf.find(b"SCRSHOT ")
    if head < 0:
        return None
    # 解析头行: SCRSHOT w h stride cf CRLF
    eol = buf.find(b"\r\n", head)
    if eol < 0:
        return None
    parts = buf[head + len("SCRSHOT "):eol].split()
    if len(parts) != 4:
        return None
    w, h, stride, cf = (int(p) for p in parts)
    raw_len = stride * h
    raw_start = eol + 2
    if len(buf) < raw_start + raw_len:
        return None  # raw 未完
    end = buf.find(b"SCRSHOT_END", raw_start + raw_len)
    if end < 0:
        return None  # 尾标未到（等更多数据）
    return (head, raw_start, raw_len, (w, h, stride, cf))


def main():
    ap = argparse.ArgumentParser(description="获取 Zephyr+LVGL 截屏帧 -> PNG")
    ap.add_argument("-p", "--port", required=True, help="串口，如 COM5")
    ap.add_argument("-b", "--baud", type=int, default=921600)
    ap.add_argument("-o", "--out", default="ui.png")
    ap.add_argument("-t", "--timeout", type=float, default=30.0, help="收帧超时秒（按波特率算）")
    args = ap.parse_args()

    try:
        import serial
    except ImportError:
        sys.exit("缺 pyserial：pip install pyserial")

    try:
        from PIL import Image
        have_pil = True
    except ImportError:
        have_pil = False

    print(f"[*] 打开 {args.port} @ {args.baud}")
    ser = serial.Serial(args.port, args.baud, timeout=1.0)
    buf = bytearray()
    tries = int(args.timeout)
    for _ in range(tries):
        chunk = ser.read(4096)
        if chunk:
            buf += chunk
            frame = find_framebuf(buf)
            if frame:
                head, raw_start, raw_len, (w, h, stride, cf) = frame
                raw = bytes(buf[raw_start:raw_start + raw_len])
                # 清除已消费数据
                del buf[:raw_start + raw_len + len(b"SCRSHOT_END")]
                print(f"[OK] 收到帧 {w}x{h} stride={stride} cf={cf} raw={raw_len}B")
                if cf == 8:  # L8 灰阶
                    data = raw[:w * h]  # 去 stride 尾
                    if have_pil:
                        img = Image.frombytes("L", (w, h), data)
                        img.save(args.out)
                        print(f"[OK] 已存 {args.out} ({w}x{h} 灰阶)")
                    else:
                        with open(args.out, "wb") as f:
                            f.write(data)
                        print(f"[i] 无 Pillow，已存 raw 灰阶 {args.out}（宽 {w}×高 {h}，需转 PNG）")
                else:
                    print(f"[i] 未支持的 cf={cf}，raw 已存 {args.out}")
                    with open(args.out, "wb") as f:
                        f.write(raw)
                ser.close()
                return 0
        sys.stdout.write(".")
        sys.stdout.flush()
    ser.close()
    print(f"\n[X] 超时 {args.timeout}s 未收到完整帧（若波特率/接线不对会停在这）")
    return 1


if __name__ == "__main__":
    sys.exit(main())
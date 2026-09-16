"""
串口调试脚本 - 自动接收并格式化展示串口数据
用法:
    python serial_debug.py [串口号] [波特率] [监听秒数]
    python serial_debug.py COM5 115200 10
    python serial_debug.py list  # 列出所有串口
"""
import serial
import serial.tools.list_ports
import time
import sys
from datetime import datetime


def list_ports():
    """列出所有可用串口"""
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print("未找到任何串口")
        return []
    print("可用串口:")
    for p in ports:
        print(f"  {p.device} - {p.description}")
    return [p.device for p in ports]


def monitor(port, baudrate=115200, duration=10, save_log=True):
    """
    监听串口数据
    port: 串口号如 'COM5'
    baudrate: 波特率
    duration: 监听时长（秒），0 表示持续监听（Ctrl+C 退出）
    save_log: 是否保存日志
    """
    print(f"打开 {port} @ {baudrate}bps, 监听 {duration}秒..." if duration > 0 else f"打开 {port} @ {baudrate}bps, 持续监听(Ctrl+C 退出)...")
    try:
        ser = serial.Serial(port, baudrate, timeout=1)
        print(f"✅ {port} 已打开")
    except Exception as e:
        print(f"❌ 打开失败: {e}")
        return

    start = time.time()
    log_lines = []
    print("=" * 70)

    try:
        while True:
            if duration > 0 and time.time() - start > duration:
                break
            line = ser.readline().decode('utf-8', errors='replace').strip()
            if line:
                ts = datetime.now().strftime('%H:%M:%S')
                print(f"[{ts}] {line}")
                log_lines.append(f"[{ts}] {line}\n")
    except KeyboardInterrupt:
        print("\n用户中断")
    finally:
        ser.close()
        elapsed = time.time() - start
        print("=" * 70)
        print(f"接收 {len(log_lines)} 行, 耗时 {elapsed:.1f}秒")

        if save_log and log_lines:
            log_file = f"serial_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
            with open(log_file, 'w', encoding='utf-8') as f:
                f.writelines(log_lines)
            print(f"日志已保存: {log_file}")


def send_and_monitor(port, baudrate, send_data, duration=10):
    """
    发送数据并监听响应
    send_data: 要发送的字节或字符串
    """
    print(f"打开 {port} @ {baudrate}bps")
    try:
        ser = serial.Serial(port, baudrate, timeout=1)
        print(f"✅ {port} 已打开")
    except Exception as e:
        print(f"❌ 打开失败: {e}")
        return

    # 发送数据
    if isinstance(send_data, str):
        send_bytes = send_data.encode('utf-8')
    else:
        send_bytes = send_data
    ser.write(send_bytes)
    print(f"→ 已发送: {send_bytes} ({len(send_bytes)} bytes)")

    start = time.time()
    log_lines = []
    print("=" * 70)

    try:
        while time.time() - start < duration:
            line = ser.readline().decode('utf-8', errors='replace').strip()
            if line:
                ts = datetime.now().strftime('%H:%M:%S')
                print(f"[{ts}] {line}")
                log_lines.append(f"[{ts}] {line}\n")
    except KeyboardInterrupt:
        print("\n用户中断")
    finally:
        ser.close()
        elapsed = time.time() - start
        print("=" * 70)
        print(f"接收 {len(log_lines)} 行, 耗时 {elapsed:.1f}秒")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法:")
        print("  python serial_debug.py list                    # 列出串口")
        print("  python serial_debug.py COM5 115200 10          # 监听10秒")
        print("  python serial_debug.py COM5 115200 0           # 持续监听(Ctrl+C退出)")
        print("  python serial_debug.py COM5 115200 10 \"hello\"  # 发送数据并监听")
        sys.exit(1)

    arg1 = sys.argv[1]
    if arg1 == 'list':
        list_ports()
    else:
        port = arg1
        baudrate = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
        duration = int(sys.argv[3]) if len(sys.argv) > 3 else 10

        if len(sys.argv) > 4:
            # 发送模式
            send_data = sys.argv[4]
            send_and_monitor(port, baudrate, send_data, duration)
        else:
            # 纯监听模式
            monitor(port, baudrate, duration)

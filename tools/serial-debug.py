"""
串口调试工具 - 自动接收并格式化展示串口数据
用法:
    serial-debug list                          # 列出所有串口
    serial-debug COM5 115200 10                # 监听10秒
    serial-debug COM5 115200 0                 # 持续监听(Ctrl+C退出)
    serial-debug COM5 115200 10 "hello"        # 发送数据并监听
    serial-debug COM5 115200 10 "hex:AA BB"    # 十六进制发送
    serial-debug COM5 0 10 -autobaud           # 自动检测波特率
    serial-debug COM5 115200 10 -hex           # 十六进制显示
    serial-debug COM5 115200 0 -raw -logfile mylog.txt
"""
import serial
import serial.tools.list_ports
import time
import sys
import argparse
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


def auto_detect_baudrate(port):
	"""
	自动检测波特率
	按常用波特率依次尝试打开串口并发送回车，检测是否有响应
	返回检测到的波特率，失败返回 None
	"""
	candidate_rates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
	print(f"自动检测波特率 ({port})...")
	for rate in candidate_rates:
		try:
			ser = serial.Serial(port, rate, timeout=0.3)
			ser.write(b'\x0D')
			time.sleep(0.2)
			data = ser.read(64)
			ser.close()
			if len(data) > 0:
				print(f"  [OK] 检测到波特率: {rate}")
				return rate
		except Exception:
			continue
	print("  [!] 未能自动检测波特率，使用默认 115200")
	return None


def format_hex(data):
	"""
	将字节数据格式化为十六进制显示
	例如: b'\x41\x42' -> "41 42  |AB|"
	"""
	if not data:
		return ''
	hex_part = ' '.join(f'{b:02X}' for b in data)
	ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data)
	return f"{hex_part}  |{ascii_part}|"


def monitor(port, baudrate=115200, duration=10, save_log=True,
			hex_mode=False, raw_mode=False, log_file=None):
	"""
	监听串口数据
	port: 串口号如 'COM5'
	baudrate: 波特率
	duration: 监听时长（秒），0 表示持续监听（Ctrl+C 退出）
	save_log: 是否保存日志
	hex_mode: 十六进制显示模式
	raw_mode: 原始字节模式（不按行切分）
	log_file: 指定日志文件名，None 则自动生成
	"""
	if duration > 0:
		print(f"打开 {port} @ {baudrate}bps, 监听 {duration}秒...")
	else:
		print(f"打开 {port} @ {baudrate}bps, 持续监听(Ctrl+C 退出)...")
	if hex_mode:
		print("[模式] 十六进制显示")
	if raw_mode:
		print("[模式] 原始字节流")
	try:
		ser = serial.Serial(port, baudrate, timeout=1)
		print(f"[OK] {port} 已打开")
	except Exception as e:
		print(f"[ERROR] 打开失败: {e}")
		return

	start = time.time()
	log_lines = []
	print("=" * 70)

	try:
		while True:
			if duration > 0 and time.time() - start > duration:
				break
			if raw_mode:
				data = ser.read(64)
				if data:
					ts = datetime.now().strftime('%H:%M:%S')
					if hex_mode:
						line = format_hex(data)
					else:
						line = data.decode('utf-8', errors='replace').strip()
					print(f"[{ts}] {line}")
					log_lines.append(f"[{ts}] {line}\n")
			else:
				line_bytes = ser.readline()
				if line_bytes:
					ts = datetime.now().strftime('%H:%M:%S')
					if hex_mode:
						line = format_hex(line_bytes)
					else:
						line = line_bytes.decode('utf-8', errors='replace').strip()
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
			if not log_file:
				log_file = f"serial_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
			with open(log_file, 'w', encoding='utf-8') as f:
				f.writelines(log_lines)
			print(f"日志已保存: {log_file}")


def send_and_monitor(port, baudrate, send_data, duration=10, hex_mode=False):
	"""
	发送数据并监听响应
	send_data: 要发送的数据
	         - 以 'hex:' 前缀表示十六进制字符串，如 'hex:AA BB CC'
	         - 普通字符串将按 UTF-8 编码发送
	hex_mode: 接收数据是否以十六进制显示
	"""
	print(f"打开 {port} @ {baudrate}bps")
	try:
		ser = serial.Serial(port, baudrate, timeout=1)
		print(f"[OK] {port} 已打开")
	except Exception as e:
		print(f"[ERROR] 打开失败: {e}")
		return

	# 处理 hex: 前缀
	if isinstance(send_data, str) and send_data.lower().startswith('hex:'):
		hex_str = send_data[4:].strip()
		try:
			send_bytes = bytes.fromhex(hex_str.replace(' ', ''))
		except ValueError as e:
			print(f"[ERROR] 十六进制解析失败: {e}")
			ser.close()
			return
		print(f"-> 发送(HEX): {hex_str} ({len(send_bytes)} bytes)")
	elif isinstance(send_data, str):
		send_bytes = send_data.encode('utf-8')
		print(f"-> 已发送: {send_data} ({len(send_bytes)} bytes)")
	else:
		send_bytes = send_data
		print(f"-> 已发送: {send_bytes} ({len(send_bytes)} bytes)")

	ser.write(send_bytes)

	start = time.time()
	log_lines = []
	print("=" * 70)

	try:
		while time.time() - start < duration:
			line_bytes = ser.readline()
			if line_bytes:
				ts = datetime.now().strftime('%H:%M:%S')
				if hex_mode:
					line = format_hex(line_bytes)
				else:
					line = line_bytes.decode('utf-8', errors='replace').strip()
				print(f"[{ts}] {line}")
				log_lines.append(f"[{ts}] {line}\n")
	except KeyboardInterrupt:
		print("\n用户中断")
	finally:
		ser.close()
		elapsed = time.time() - start
		print("=" * 70)
		print(f"接收 {len(log_lines)} 行, 耗时 {elapsed:.1f}秒")


def parse_args(argv):
	"""
	解析命令行参数
	支持位置参数和选项参数（-hex, -raw, -autobaud, -logfile）
	"""
	parser = argparse.ArgumentParser(
		description='串口调试工具',
		formatter_class=argparse.RawDescriptionHelpFormatter,
		epilog="示例:\n"
			"  serial-debug list\n"
			"  serial-debug COM5 115200 10\n"
			"  serial-debug COM5 115200 0\n"
			'  serial-debug COM5 115200 10 "hello"\n'
			'  serial-debug COM5 115200 10 "hex:AA BB"\n'
			"  serial-debug COM5 0 10 -autobaud\n"
			"  serial-debug COM5 115200 10 -hex\n"
			"  serial-debug COM5 115200 0 -raw -logfile mylog.txt\n"
	)
	parser.add_argument('port', nargs='?', default=None, help='串口号 (如 COM5) 或 list')
	parser.add_argument('baudrate', nargs='?', type=int, default=115200, help='波特率 (默认 115200, 0=自动检测)')
	parser.add_argument('duration', nargs='?', type=int, default=10, help='监听时长秒数 (0=持续)')
	parser.add_argument('send', nargs='?', default=None, help='要发送的数据 (支持 hex: 前缀)')
	parser.add_argument('-hex', dest='hex_mode', action='store_true', help='十六进制显示接收数据')
	parser.add_argument('-raw', dest='raw_mode', action='store_true', help='原始字节模式 (不按行切分)')
	parser.add_argument('-autobaud', dest='autobaud', action='store_true', help='自动检测波特率')
	parser.add_argument('-logfile', dest='logfile', default=None, help='指定日志文件名')
	return parser.parse_args(argv)


if __name__ == '__main__':
	args = parse_args(sys.argv[1:])

	if not args.port:
		print("用法:")
		print("  serial-debug list                                # 列出串口")
		print("  serial-debug COM5 115200 10                      # 监听10秒")
		print("  serial-debug COM5 115200 0                       # 持续监听(Ctrl+C退出)")
		print('  serial-debug COM5 115200 10 "hello"              # 发送数据并监听')
		print('  serial-debug COM5 115200 10 "hex:AA BB"          # 十六进制发送')
		print("  serial-debug COM5 0 10 -autobaud                 # 自动检测波特率")
		print("  serial-debug COM5 115200 10 -hex                 # 十六进制显示")
		print("  serial-debug COM5 115200 0 -raw -logfile log.txt # 原始模式+指定日志")
		sys.exit(1)

	if args.port == 'list':
		list_ports()
	else:
		port = args.port
		baudrate = args.baudrate
		duration = args.duration

		# 自动检测波特率
		if args.autobaud or baudrate == 0:
			detected = auto_detect_baudrate(port)
			if detected:
				baudrate = detected
			else:
				baudrate = 115200

		if args.send:
			send_and_monitor(port, baudrate, args.send, duration, hex_mode=args.hex_mode)
		else:
			monitor(port, baudrate, duration,
					hex_mode=args.hex_mode, raw_mode=args.raw_mode,
					log_file=args.logfile)
